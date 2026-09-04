<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ListingDocument;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPublicationBlock;
use App\Services\AuditLogService;
use App\Services\ListingWorkflowService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ListingReviewController extends Controller
{
    public function __construct(
        private readonly ListingWorkflowService $workflow,
        private readonly AuditLogService $audit,
    ) {}

    public function queue(Request $request): JsonResponse
    {
        $v = $request->validate([
            'review_status' => ['nullable', Rule::in(['submitted','under_review','returned_for_correction','approved','rejected_blocked'])],
            'per_page' => ['nullable','integer','min:1','max:50'],
        ]);
        $user = $request->user();
        $isSupportWorker = $user?->hasRole('support_agent') === true
            && ! $user->hasPermission('support.manage');

        $q = Property::query()
            ->with(['images','documents','user','propertyAsset'])
            ->whereNotIn('review_status', ['draft']);

        if (! empty($v['review_status'])) {
            $q->where('review_status', $v['review_status']);
        } else {
            $q->whereIn('review_status', ['submitted','under_review']);
        }

        if ($isSupportWorker) {
            $q->where(function ($assignment) use ($user): void {
                $assignment
                    ->where(function ($fresh): void {
                        $fresh->where('review_status', 'submitted')
                            ->whereNull('review_assigned_to_user_id');
                    })
                    ->orWhere(function ($mine) use ($user): void {
                        $mine->where('review_status', 'under_review')
                            ->where('review_assigned_to_user_id', $user->id);
                    });
            });
        }

        $page = $q
            ->orderByRaw("CASE WHEN review_status='submitted' THEN 0 ELSE 1 END")
            ->orderBy('submitted_at')
            ->paginate((int) ($v['per_page'] ?? 25));

        return response()->json([
            'data' => collect($page->items())
                ->map(fn (Property $p) => $this->data($p, false))
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }    public function show(Request $request, Property $property): JsonResponse
    {
        $user = $request->user();
        $isSupportWorker = $user?->hasRole('support_agent') === true
            && ! $user->hasPermission('support.manage');
        $assignedTo = (int) ($property->review_assigned_to_user_id ?? 0);
        if ($isSupportWorker && $assignedTo > 0 && $assignedTo !== (int) $user->id) {
            abort(403, 'تم استلام هذا الإعلان بواسطة موظف دعم آخر.');
        }

        return response()->json([
            'data' => $this->data(
                $property->load(['images','documents','user','propertyAsset','reviews.actor']),
                true
            ),
        ]);
    }public function start(Request $request, Property $property): JsonResponse { return response()->json(['message'=>'Review started.','data'=>$this->data($this->workflow->startReview($request->user(),$property,$request),false)]); }
    public function returnForCorrection(Request $request, Property $property): JsonResponse {$v=$request->validate(['reason'=>['required','string','min:5','max:2000']]);return response()->json(['message'=>'Listing returned for correction.','data'=>$this->data($this->workflow->returnForCorrection($request->user(),$property,$v['reason'],$request),false)]);}
    public function approve(Request $request, Property $property): JsonResponse {$v=$request->validate(['reason'=>['nullable','string','max:2000']]);return response()->json(['message'=>'Listing approved and published.','data'=>$this->data($this->workflow->approve($request->user(),$property,$v['reason']??null,$request),false)]);}
    public function rejectFinal(Request $request, Property $property): JsonResponse {$v=$request->validate(['reason'=>['required','string','min:10','max:3000']]);return response()->json(['message'=>'Physical property blocked for this publication purpose.','data'=>$this->data($this->workflow->finalRejectAndBlock($request->user(),$property,$v['reason'],$request),false)]);}
    public function linkPropertyAsset(Request $request, Property $property): JsonResponse {$v=$request->validate(['property_asset_id'=>['required','integer','exists:property_assets,id'],'reason'=>['required','string','min:5','max:2000']]);$asset=PropertyAsset::query()->findOrFail((int)$v['property_asset_id']);return response()->json(['message'=>'Listing linked to physical property identity.','data'=>$this->data($this->workflow->linkAsset($request->user(),$property,$asset,$v['reason'],$request),false)]);}

    public function blocks(Request $request): JsonResponse
    {
        $v=$request->validate(['active'=>['nullable','boolean'],'per_page'=>['nullable','integer','min:1','max:100']]);$q=PropertyPublicationBlock::query()->with(['propertyAsset','blockedBy','liftedBy'])->latest('id');if(array_key_exists('active',$v))$q->where('is_active',(bool)$v['active']);$page=$q->paginate((int)($v['per_page']??50));
        return response()->json(['data'=>collect($page->items())->map(fn($b)=>$this->blockData($b))->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()]]);
    }
    public function liftBlock(Request $request, PropertyPublicationBlock $block): JsonResponse {$v=$request->validate(['reason'=>['required','string','min:10','max:3000']]);return response()->json(['message'=>'Publication block lifted.','data'=>$this->blockData($this->workflow->liftBlock($request->user(),$block,$v['reason'],$request))]);}



    public function document(Request $request, ListingDocument $document)
    {
        $document->loadMissing('property');$user=$request->user();$isOwner=$document->property&&(int)$document->property->user_id===(int)$user->id;abort_unless($isOwner||$user->hasPermission('listings.moderate'),403);abort_unless(app(\App\Services\CloudAssetStorageService::class)->existsPrivate($document->path),404);
        $this->audit->record($user,'listing.proof_document_viewed',$document,['listing_id'=>$document->property_id,'kind'=>$document->kind],$request,$document->property?->user_id);
        return app(\App\Services\CloudAssetStorageService::class)->downloadPrivate($document->path,$document->original_name,['Content-Type'=>$document->mime_type?:'application/octet-stream']);
    }

    private function data(Property $p,bool $full): array
    {
        $p->loadMissing(['user.accountVerificationProfile.documents','propertyAsset','documents','images']);$block=$p->propertyAsset?->publicationBlocks()->where('purpose',$p->purpose)->where('is_active',true)->latest('id')->first();
        $profile=$p->user?->accountVerificationProfile;
        $data=[
            'id'=>$p->id,
            'title'=>$p->title,
            'purpose'=>$p->purpose,
            'type'=>$p->type,
            'tenure_type'=>$p->tenure_type,
            'price'=>(float)$p->price,
            'status'=>$p->status,
            'review_status'=>$p->review_status,
            'submitted_at'=>$p->submitted_at?->toIso8601String(),
            'published_at'=>$p->published_at?->toIso8601String(),
            'last_review_reason'=>$p->last_review_reason,
            'owner'=>[
                'id'=>$p->user?->id,
                'name'=>$p->user?->name,
                'email'=>$p->user?->email,
                'phone'=>$p->user?->phone,
                'verification_type'=>$profile?->type,
                'verification_status'=>$profile?->status ?? 'not_submitted',
                'identity_reviewed'=>$profile?->isApproved() === true,
            ],
            'ownership_relationship'=>[
                'document_type'=>$p->ownership_document_type,
                'document_owner_name'=>$p->document_owner_name,
                'relationship_type'=>$p->owner_relationship_type,
                'relationship_note'=>$p->owner_relationship_note,
                'name_matches_account'=>$p->document_owner_name !== null && $p->user !== null
                    ? $this->normalizedName($p->document_owner_name) === $this->normalizedName($p->user->name)
                    : null,
                'document_present'=>$p->documents->contains(fn($d)=>$d->kind==='ownership_proof'),
            ],
            'property_asset'=>[
                'id'=>$p->propertyAsset?->id,
                'identity_hash'=>$p->propertyAsset?->identity_hash,
                'latitude'=>$p->propertyAsset?->canonical_latitude,
                'longitude'=>$p->propertyAsset?->canonical_longitude,
            ],
            'images'=>$p->images->map(fn($image)=>['id'=>$image->id,'url'=>'/api/property-media/'.$image->id,'is_primary'=>(bool)$image->is_primary,'sort_order'=>(int)$image->sort_order])->values(),
            'proof_documents'=>$p->documents->map(fn($d)=>['id'=>$d->id,'kind'=>$d->kind,'original_name'=>$d->original_name,'mime_type'=>$d->mime_type,'size_bytes'=>$d->size_bytes,'url'=>'/api/listing-documents/'.$d->id])->values(),
            'active_publication_block'=>$block?$this->blockData($block):null,
            'broker_verification'=>['required'=>false,'approval_allowed'=>true,'reason'=>'broker_region_verification_retired','geo_cell_id'=>null,'geo_cell_name'=>null,'broker'=>null,'latest'=>null],
        ];
        if($full){$p->loadMissing('reviews.actor');$data['review_history']=$p->reviews->map(fn($r)=>['id'=>$r->id,'action'=>$r->action,'from'=>$r->from_review_status,'to'=>$r->to_review_status,'reason'=>$r->reason,'actor_name'=>$r->actor?->name,'created_at'=>$r->created_at?->toIso8601String()])->values();$data['address']=$p->address;$data['latitude']=(float)$p->latitude;$data['longitude']=(float)$p->longitude;$data['description']=$p->description;$data['area_m2']=$p->area_m2;$data['area_value']=$p->area_value!==null?(float)$p->area_value:null;$data['area_unit']=$p->area_unit;$data['bedrooms']=$p->bedrooms;$data['bathrooms']=$p->bathrooms;$data['has_parking']=$p->has_parking;$data['building_facade']=$p->building_facade;}
        return $data;
    }
    private function normalizedName(?string $value): string
    {
        $text=mb_strtolower(trim((string)$value));
        $text=preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u','',$text)??$text;
        $text=strtr($text,['أ'=>'ا','إ'=>'ا','آ'=>'ا','ى'=>'ي','ؤ'=>'و','ئ'=>'ي','ة'=>'ه']);
        return preg_replace('/\s+/u',' ',$text)??$text;
    }

    private function blockData(PropertyPublicationBlock $b): array {return ['id'=>$b->id,'property_asset_id'=>$b->property_asset_id,'purpose'=>$b->purpose,'is_active'=>(bool)$b->is_active,'reason'=>$b->reason,'blocked_by_user_id'=>$b->blocked_by_user_id,'blocked_at'=>$b->blocked_at?->toIso8601String(),'lifted_by_user_id'=>$b->lifted_by_user_id,'lifted_reason'=>$b->lifted_reason,'lifted_at'=>$b->lifted_at?->toIso8601String()];}
}
