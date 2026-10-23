<?php
namespace App\Services;

use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\User;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Partial account checkpoints; only the normal Property workflow can submit them. */
class ListingEditorDraftService
{
    public function owned(User $actor, string $key, bool $lock = false): ListingEditorDraft
    {
        abort_unless(Str::isUuid($key), 404);
        $query = ListingEditorDraft::query()->where('user_id',$actor->id)->where('client_key',$key);
        return ($lock ? $query->lockForUpdate() : $query)->firstOrFail();
    }

    public function assertEditable(User $actor, ?Property $property = null): void
    {
        abort_unless($actor->isActive() && $actor->hasApprovedVerificationProfile() && $actor->canCreateListings(),403);
        if ($property) {
            abort_unless((int)$property->user_id === (int)$actor->id,404);
            abort_if($property->status === 'archived' || in_array($property->review_status,['submitted','under_review','rejected_blocked'],true),409);
        }
    }

    public function assertRevision(ListingEditorDraft $draft, int $expected): void
    {
        if ($draft->revision !== $expected) throw new HttpResponseException(response()->json([
            'code'=>'draft_revision_conflict','message'=>'هذه المسودة تغيرت على جهاز آخر. افتح أحدث نسخة قبل المتابعة.',
        ],409));
    }

    public function clean(array $payload): array
    {
        $allowed = ['checkpoint_key','media_version','editor_version','sai_amount_type','rental_conditions','unit_occupies_entire_floor','sai_touched','sai_terms_accepted',
            'units_per_floor','same_floor_units','step','purpose','type','area_unit','tenure_type','parking','elevator','facade','ownership_document_type','relationship_type',
            'latitude','longitude','land_boundary','replace_images','price_display_mode','server_property_id','proof_needs_reselection',
            'type_confirmed','purpose_confirmed','completion_only','image_order','fields'];
        $payload = array_intersect_key($payload,array_flip($allowed));
        $fields = array_intersect_key((array)($payload['fields'] ?? []),array_flip([
            'title','description','ai_listing_brief','price','monthly_rent','rental_term_months','advance_months','area',
            'floors_count','shop_openings','bedrooms','bathrooms','governorate','district','street','building_reference','unit_number','floor_number','phone','whatsapp',
            'document_owner_name','relationship_note','broker_sai_rate_percent','fixed_sai_amount']));
        foreach ($fields as $key=>$value) { abort_unless(is_scalar($value) || $value === null,422); $fields[$key] = mb_substr((string)$value,0,$key === 'ai_listing_brief' ? 10000 : ($key === 'description' ? 5000 : 1500)); }
        if (isset($payload['units_per_floor'])) {
            abort_unless(is_array($payload['units_per_floor']) && array_is_list($payload['units_per_floor']) && count($payload['units_per_floor'])<=50,422);
            $payload['units_per_floor']=array_map(function ($value) { abort_unless(is_scalar($value) || $value===null,422); return mb_substr((string)$value,0,3); },$payload['units_per_floor']);
        }
        $payload['same_floor_units']=($payload['same_floor_units'] ?? false) === true;
        $context = $payload + ['unit_occupies_entire_floor'=>false];
        $aliases = ['area'=>'area_value','parking'=>'has_parking','elevator'=>'has_elevator','facade'=>'building_facade','land_boundary'=>'land_boundary_geojson'];
        $schema = app(DynamicPropertySchema::class);
        foreach ($fields as $key=>$_) if (! $schema->applies($aliases[$key] ?? $key,$context)) unset($fields[$key]);
        foreach ($payload as $key=>$_) if (! $schema->applies($aliases[$key] ?? $key,$context)) unset($payload[$key]);
        $checked = $schema->validateApartmentFloor($fields + ['type'=>$payload['type'] ?? null], 'fields.floor_number');
        if (isset($checked['floor_number'])) $fields['floor_number'] = $checked['floor_number'];
        if (($payload['type'] ?? '') === 'shop') {
            if (is_numeric($fields['area'] ?? null)) $fields['area'] = (string)((float)$fields['area'] * ($schema->definition()['area_units_to_sqm'][$payload['area_unit'] ?? 'sqm'] ?? 1));
            $payload['area_unit']='sqm';
        }
        if (($payload['purpose'] ?? '') === 'rent') unset($fields['price']);
        $payload['step']=max(0,min(3,(int)($payload['step'] ?? 0)));
        $payload['image_order']=array_values(array_unique(array_filter((array)($payload['image_order'] ?? []),fn($key)=>is_string($key) && (Str::isUuid($key) || preg_match('/^property-[1-9][0-9]*$/D',$key)))));
        $payload['fields']=$fields;
        return $payload;
    }

    public function present(ListingEditorDraft $draft): array
    {
        $payload = $draft->payload; $fields = $payload['fields'] ?? [];
        $title=trim((string)($fields['title'] ?? ''));
        if ($title === '') {
            $knownType=($payload['type_confirmed'] ?? true) ? ($payload['type'] ?? '') : '';
            $title=ListingAiService::TYPES[$knownType] ?? 'إعلان غير مكتمل';
            if (($payload['purpose_confirmed'] ?? true) && in_array($payload['purpose'] ?? '',['sale','rent'],true)) $title.= $payload['purpose'] === 'rent' ? ' للإيجار' : ' للبيع';
            $place=trim((string)($fields['district'] ?? $fields['governorate'] ?? ''));
            if ($place!=='') $title.=' - '.$place;
        }
        $facts=$payload+$fields;
        $facts['area_value']=$fields['area'] ?? null; $facts['has_parking']=$payload['parking'] ?? null; $facts['building_facade']=$payload['facade'] ?? null;
        $required=array_merge(['title','latitude','longitude'],app(DynamicPropertySchema::class)->required($facts));
        $complete=0;
        foreach ($required as $key) if (isset($facts[$key]) && $facts[$key] !== '' && (! in_array($key,['area_value','bedrooms','bathrooms'],true) || (float)$facts[$key]>0)) $complete++;
        $images=[];
        foreach ($draft->images as $key=>$_) {
            $url=url('/api/listing-editor-drafts/'.$draft->client_key.'/images/'.$key);
            $images[]=['key'=>$key,'url'=>$url,'status'=>'complete','variants'=>array_combine(array_keys(config('listing_media.variants')),array_map(fn($v)=>$url.'?variant='.$v,array_keys(config('listing_media.variants'))))];
        }
        return ['key'=>$draft->client_key,'property_id'=>$draft->property_id,'revision'=>$draft->revision,'payload'=>$payload,'images'=>$images,
            'title'=>$title,'progress'=>(int)round(100*$complete/max(1,count($required))),'updated_at'=>$draft->updated_at?->toIso8601String()];
    }

    /** Called inside the Property transaction, after the account row is locked. */
    public function attach(Request $request, Property $property): void
    {
        $key=$request->input('editor_draft_key'); if (!$key) return;
        $draft=$this->owned($request->user(),$key,true);
        $this->assertRevision($draft,(int)$request->input('editor_draft_revision',-1));
        abort_if($draft->property_id !== null && $draft->property_id !== (int)$property->id,409);
        $images=$draft->images;
        $removed=[];
        $payload=$draft->payload;
        if (($draft->payload['media_version'] ?? 0) === 1) {
            $wanted=$draft->payload['image_order'] ?? [];
            foreach ($wanted as $token) if (str_starts_with($token,'property-')) {
                abort_unless($property->images()->whereKey((int)substr($token,9))->exists(),422,'الصورة لا تنتمي لهذا الإعلان.');
            }
            foreach ($property->images()->get() as $image) if (!in_array('property-'.$image->id,$wanted,true)) {
                $removed[]=$image->path; $image->delete();
            }
            foreach ($images as $token=>$path) if (!in_array($token,$wanted,true)) { $removed[]=$path; unset($images[$token]); }
            // An interrupted/removed local file cannot be silently skipped during promotion.
            foreach ($wanted as $token) if (Str::isUuid($token)) abort_unless(isset($images[$token]),422,'لم يكتمل رفع الصور. أعد محاولة الملف المتعثر.');
        }
        abort_if($property->images()->count()+count($images)>12,422,'يمكن رفع 12 صورة على الأكثر.');
        $order=array_unique(array_merge($draft->payload['image_order'] ?? [],array_keys($images)));
        $sort=$property->images()->max('sort_order') ?? -1;
        $attached=[];
        foreach ($order as $imageKey) {
            if (!isset($images[$imageKey])) continue;
            $attached[$imageKey]=$property->images()->firstOrCreate(['path'=>$images[$imageKey]],['sort_order'=>++$sort]);
        }
        if (($draft->payload['media_version'] ?? 0) === 1) {
            $promoted=[];$committedOrder=[];
            foreach ($draft->payload['image_order'] ?? [] as $position=>$token) {
                $image=str_starts_with($token,'property-') ? $property->images()->find((int)substr($token,9)) : ($attached[$token] ?? null);
                if ($image) {
                    $image->forceFill(['sort_order'=>$position,'is_primary'=>$position===0])->save();
                    $committedOrder[]='property-'.$image->id;
                    if (Str::isUuid($token)) $promoted[$token]='property-'.$image->id;
                }
            }
            // Server-written aliases let a client recover a lost Property response without uploading successful files again.
            $payload['image_order']=$committedOrder;
            $payload['promoted_image_keys']=$promoted;
        }
        $draft->forceFill(['property_id'=>$property->id,'payload'=>$payload,'images'=>[],'revision'=>$draft->revision+1])->save();
        if ($removed) DB::afterCommit(fn()=>$this->removeFiles($removed));
    }

    public function removeFiles(array $paths): void
    {
        foreach ($paths as $path) app(ListingImageService::class)->removeIfUnused($path);
    }
}
