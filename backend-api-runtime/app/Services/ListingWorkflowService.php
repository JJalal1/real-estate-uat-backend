<?php
namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\ListingReview;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPublicationBlock;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class ListingWorkflowService
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly PropertyAssetService $assets,
        private readonly RegionService $regions,
        private readonly BrokerListingVerificationService $brokerVerification,
    ) {}

    public function submit(User $actor, Property $listing, Request $request): Property
    {
        if (! in_array($listing->review_status, ['draft','returned_for_correction'], true)) {
            throw new ConflictHttpException('This listing is not in a submittable state.');
        }
        if ($listing->images()->count() < 1) throw new ConflictHttpException('At least one listing image is required before submission.');
        $this->assertAdvertiserCanPublish($actor, $listing);
        $asset=$listing->propertyAsset()->firstOrFail();
        $this->assets->assertPurposeNotBlocked($asset, $listing->purpose);
        $this->assets->assertNotAlreadyPublished($asset, $listing->purpose, $listing->id);
        $this->regions->assertListingAllowed($actor, (float)$listing->latitude, (float)$listing->longitude);
        return DB::transaction(function() use($actor,$listing,$request){
            $from=$listing->review_status;
            $listing->forceFill(['status'=>'pending','review_status'=>'submitted','submitted_at'=>now(),'reviewed_at'=>null,'last_review_reason'=>null])->save();
            $this->review($actor,$listing,'submitted',$from,'submitted',null,[]);
            $this->audit->record($actor,'listing.submitted',$listing,['review_status'=>'submitted'],$request,$actor->id);
            return $listing->fresh(['images','documents','propertyAsset']);
        });
    }

    public function startReview(User $actor, Property $listing, Request $request): Property
    {
        if (! in_array($listing->review_status, ['submitted','under_review'], true)) throw new ConflictHttpException('Listing is not awaiting review.');
        if ($listing->review_status === 'under_review') return $listing->fresh();
        return DB::transaction(function()use($actor,$listing,$request){$from=$listing->review_status;$listing->forceFill(['status'=>'pending','review_status'=>'under_review'])->save();$this->review($actor,$listing,'review_started',$from,'under_review');$this->audit->record($actor,'listing.review_started',$listing,[],$request,$listing->user_id);return $listing->fresh();});
    }

    public function returnForCorrection(User $actor, Property $listing, string $reason, Request $request): Property
    {
        $this->assertReviewable($listing);
        return DB::transaction(function()use($actor,$listing,$reason,$request){$from=$listing->review_status;$listing->forceFill(['status'=>'draft','review_status'=>'returned_for_correction','reviewed_at'=>now(),'last_review_reason'=>$reason])->save();$this->review($actor,$listing,'returned_for_correction',$from,'returned_for_correction',$reason);$this->audit->record($actor,'listing.returned_for_correction',$listing,['reason'=>$reason],$request,$listing->user_id);return $listing->fresh();});
    }

    public function approve(User $actor, Property $listing, ?string $reason, Request $request): Property
    {
        $this->assertReviewable($listing);
        $owner=$listing->user()->firstOrFail();
        $this->assertAdvertiserCanPublish($owner, $listing);
        $this->brokerVerification->assertApprovalAllowed($listing);
        return DB::transaction(function()use($actor,$listing,$owner,$reason,$request){
            $asset=PropertyAsset::query()->whereKey($listing->property_asset_id)->lockForUpdate()->firstOrFail();
            $this->assets->assertPurposeNotBlocked($asset,$listing->purpose);
            $this->assets->assertNotAlreadyPublished($asset,$listing->purpose,$listing->id);
            $this->regions->assertListingAllowed($owner,(float)$listing->latitude,(float)$listing->longitude);
            $from=$listing->review_status;
            $listing->forceFill(['status'=>'published','review_status'=>'approved','published_at'=>now(),'reviewed_at'=>now(),'last_review_reason'=>$reason])->save();
            $this->review($actor,$listing,'approved',$from,'approved',$reason);
            $this->audit->record($actor,'listing.approved',$listing,['reason'=>$reason],$request,$listing->user_id);
            return $listing->fresh();
        });
    }

    public function finalRejectAndBlock(User $actor, Property $listing, string $reason, Request $request): Property
    {
        $this->assertReviewable($listing);$asset=$listing->propertyAsset()->firstOrFail();
        return DB::transaction(function()use($actor,$listing,$asset,$reason,$request){
            $existing=PropertyPublicationBlock::query()->where('property_asset_id',$asset->id)->where('purpose',$listing->purpose)->where('is_active',true)->lockForUpdate()->first();
            $block=$existing ?: PropertyPublicationBlock::query()->create(['property_asset_id'=>$asset->id,'purpose'=>$listing->purpose,'is_active'=>true,'reason'=>$reason,'blocked_by_user_id'=>$actor->id,'source_listing_id'=>$listing->id,'blocked_at'=>now()]);
            $affected=Property::query()->where('property_asset_id',$asset->id)->where('purpose',$listing->purpose)->get();
            foreach($affected as $item){$from=$item->review_status;$item->forceFill(['status'=>'rejected','review_status'=>'rejected_blocked','reviewed_at'=>now(),'published_at'=>null,'last_review_reason'=>$reason])->save();$action=$item->id===$listing->id?'final_rejected_blocked':'property_block_enforced';$this->review($actor,$item,$action,$from,'rejected_blocked',$reason,['publication_block_id'=>$block->id]);}
            $this->audit->record($actor,'property.publication_block_created',$block,['property_asset_id'=>$asset->id,'purpose'=>$listing->purpose,'reason'=>$reason],$request,$listing->user_id);
            return $listing->fresh();
        });
    }

    public function liftBlock(User $actor, PropertyPublicationBlock $block, string $reason, Request $request): PropertyPublicationBlock
    {
        if (! $block->is_active) throw new ConflictHttpException('Publication block is already inactive.');
        return DB::transaction(function()use($actor,$block,$reason,$request){$block->forceFill(['is_active'=>false,'lifted_by_user_id'=>$actor->id,'lifted_reason'=>$reason,'lifted_at'=>now()])->save();$this->audit->record($actor,'property.publication_block_lifted',$block,['property_asset_id'=>$block->property_asset_id,'purpose'=>$block->purpose,'reason'=>$reason],$request);return $block->fresh();});
    }

    public function linkAsset(User $actor, Property $listing, PropertyAsset $asset, string $reason, Request $request): Property
    {
        return DB::transaction(function()use($actor,$listing,$asset,$reason,$request){$old=$listing->property_asset_id;$listing->forceFill(['property_asset_id'=>$asset->id])->save();$this->review($actor,$listing,'property_identity_linked',$listing->review_status,$listing->review_status,$reason,['old_property_asset_id'=>$old,'new_property_asset_id'=>$asset->id]);$this->audit->record($actor,'listing.property_identity_linked',$listing,['old_property_asset_id'=>$old,'new_property_asset_id'=>$asset->id,'reason'=>$reason],$request,$listing->user_id);if($this->assets->activeBlock($asset,$listing->purpose)){$listing->forceFill(['status'=>'rejected','review_status'=>'rejected_blocked','reviewed_at'=>now(),'published_at'=>null,'last_review_reason'=>'Linked to an actively blocked physical property.'])->save();$this->review($actor,$listing,'linked_to_blocked_property','under_review','rejected_blocked','Linked to an actively blocked physical property.');}return $listing->fresh();});
    }

    private function assertAdvertiserCanPublish(User $advertiser, Property $property): void
    {
        $profile = $advertiser->verificationProfile();
        if ($profile) {
            if (! $profile->isApproved()) {
                throw new ConflictHttpException('يجب اعتماد نوع الحساب من فريق التحقق قبل إرسال إعلان للمراجعة.');
            }

            if (in_array($profile->type, [
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ], true)) {
                return;
            }

            if ($profile->type === AccountVerificationProfile::TYPE_OWNER) {
                if (! $property->documents()->where('kind', 'ownership_proof')->exists()) {
                    throw ValidationException::withMessages([
                        'ownership_proof' => ['يجب إرفاق مستند يثبت الملكية أو العلاقة بهذا العقار قبل الإرسال للمراجعة.'],
                    ]);
                }
                if (! $property->ownership_document_type || ! $property->document_owner_name || ! $property->owner_relationship_type) {
                    throw ValidationException::withMessages([
                        'ownership_relationship' => ['حدد نوع مستند الملكية واسم صاحب الحق وصفة علاقتك بالعقار.'],
                    ]);
                }
                if ($property->owner_relationship_type === 'owner'
                    && $this->normalizedName($property->document_owner_name) !== $this->normalizedName($advertiser->name)) {
                    throw ValidationException::withMessages([
                        'owner_relationship_type' => ['الاسم المدخل من مستند العقار لا يطابق اسم الحساب. اختر صفتك الصحيحة مثل وكيل أو وارث أو شريك.'],
                    ]);
                }
                if ($property->owner_relationship_type === 'other' && trim((string) $property->owner_relationship_note) === '') {
                    throw ValidationException::withMessages([
                        'owner_relationship_note' => ['وضح صفتك أو علاقتك بالعقار.'],
                    ]);
                }
                return;
            }
        }

        // Compatibility with historical test/local identities that predate the
        // unified owner/broker/office verification policy. Current WhatsApp UAT
        // accounts use identity policy >= 1 and therefore must select a profile.
        if ((int) $advertiser->identity_policy_version === 0) {
            if (! $property->documents()->where('kind', 'ownership_or_authorization')->exists()) {
                throw ValidationException::withMessages([
                    'proof_documents' => ['أرفق إثبات ملكية أو تفويض قبل إرسال الإعلان للمراجعة.'],
                ]);
            }
            return;
        }

        if ($advertiser->isBrokerVerified()) return;

        throw new ConflictHttpException('اختر نوع الحساب من حسابي وأكمل التحقق قبل إرسال إعلان للمراجعة.');
    }

    private function normalizedName(?string $value): string
    {
        $text = mb_strtolower(trim((string) $value));
        $text = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $text) ?? $text;
        $text = strtr($text, ['أ'=>'ا','إ'=>'ا','آ'=>'ا','ى'=>'ي','ؤ'=>'و','ئ'=>'ي','ة'=>'ه']);
        return preg_replace('/\s+/u', ' ', $text) ?? $text;
    }

    private function assertReviewable(Property $listing): void { if(!in_array($listing->review_status,['submitted','under_review'],true)) throw new ConflictHttpException('Listing is not reviewable in its current state.'); }

    private function review(?User $actor, Property $listing, string $action, ?string $from, ?string $to, ?string $reason=null, array $metadata=[]): ListingReview
    {
        return ListingReview::query()->create(['listing_id'=>$listing->id,'actor_user_id'=>$actor?->id,'actor_name_snapshot'=>$actor?->name,'action'=>$action,'from_review_status'=>$from,'to_review_status'=>$to,'reason'=>$reason,'listing_snapshot'=>$this->snapshot($listing),'metadata'=>$metadata,'created_at'=>now()]);
    }

    private function snapshot(Property $listing): array
    {
        return ['id'=>$listing->id,'user_id'=>$listing->user_id,'property_asset_id'=>$listing->property_asset_id,'title'=>$listing->title,'purpose'=>$listing->purpose,'type'=>$listing->type,'price'=>(float)$listing->price,'latitude'=>(float)$listing->latitude,'longitude'=>(float)$listing->longitude,'status'=>$listing->status,'review_status'=>$listing->review_status];
    }
}
