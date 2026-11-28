<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\User;
use App\Services\ListingEditorDraftService;
use App\Services\ListingImageService;
use App\Services\PropertyIdentityService;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ListingEditorDraftController extends Controller
{
    public function __construct(private readonly ListingEditorDraftService $drafts) {}

    public function index(Request $request)
    {
        $this->drafts->consolidateLegacyRecoveries($request->user());
        $rows=ListingEditorDraft::query()->where('user_id',$request->user()->id)->where('created_at','>',now()->subDays(7))
            ->where(fn($q)=>$q->whereNull('payload->draft_kind')->orWhere('payload->draft_kind','!=','retired'))
            ->where(function($q):void {$q->whereNull('property_id')->orWhereHas('property',fn($p)=>$p->where('status','draft')->whereNotIn('review_status',['submitted','under_review','rejected_blocked']));})
            ->orderByDesc('updated_at')->orderByDesc('id')->paginate(50);
        return response()->json(['data'=>$rows->getCollection()->map(fn($d)=>$this->drafts->present($d)),
            'meta'=>['current_page'=>$rows->currentPage(),'last_page'=>$rows->lastPage(),'recovery_contract'=>1,'restart_contract'=>1]]);
    }
    public function show(Request $request,string $key) { return response()->json(['data'=>$this->drafts->present($this->drafts->owned($request->user(),$key))]); }

    public function save(Request $request,string $key)
    {
        abort_unless(Str::isUuid($key),404);
        $v=$request->validate(['payload'=>['required','array'],'first_saved_at'=>['nullable','date'],'expected_revision'=>['required','integer','min:0'],'property_id'=>['nullable','integer','min:1'],
            'payload.type'=>['nullable',\Illuminate\Validation\Rule::in(array_keys(app(\App\Services\DynamicPropertySchema::class)->definition()['types']))],
            'payload.currency'=>['sometimes','required','string','regex:/^[A-Z]{3}$/D'],
            'payload.purpose'=>['nullable','in:sale,rent'],'payload.step'=>['nullable','integer','between:0,3'],
            'payload.latitude'=>['nullable','numeric','between:-90,90'],'payload.longitude'=>['nullable','numeric','between:-180,180'],
            'payload.fields'=>['nullable','array'],'payload.image_order'=>['nullable','array','max:12'],
            'payload.image_order.*'=>['string','distinct',function($attribute,$value,$fail){ if (!Str::isUuid($value) && !preg_match('/^property-[1-9][0-9]*$/D',$value)) $fail('مرجع الصورة غير صالح.'); }],
            'payload.checkpoint_key'=>['nullable','uuid'],'payload.media_version'=>['nullable','integer','in:1'],
            'payload.editor_version'=>['nullable','integer','between:1,100'],
            'payload.draft_kind'=>['nullable','in:recovery,saved'],'payload.entry_method'=>['nullable','in:manual,assistant'],
            'payload.type_confirmed'=>['nullable','boolean'],'payload.purpose_confirmed'=>['nullable','boolean'],
            'payload.completion_only'=>['nullable','boolean'],'payload.completion_reviewing'=>['nullable','boolean'],
            'payload.sai_amount_type'=>['nullable','in:percentage,fixed'],'payload.sai_touched'=>['nullable','boolean'],
            'payload.sai_terms_accepted'=>['nullable','boolean'],'payload.rental_conditions'=>['nullable','array','max:24'],
            'payload.unit_occupies_entire_floor'=>['nullable','boolean'],'payload.units_per_floor'=>['nullable','array','max:50'],
            'payload.same_floor_units'=>['nullable','boolean'],'payload.area_unit'=>['nullable','string','max:30'],
            'payload.tenure_type'=>['nullable','in:freehold,waqf'],'payload.parking'=>['nullable','in:yes,no'],
            'payload.elevator'=>['nullable','in:yes,no'],'payload.facade'=>['nullable','string','max:50'],
            'payload.ownership_document_type'=>['nullable','string','max:50'],'payload.relationship_type'=>['nullable','string','max:50'],
            'payload.land_boundary'=>['nullable','array'],'payload.replace_images'=>['nullable','boolean'],
            'payload.price_display_mode'=>['nullable','in:excludes_sai,includes_sai'],'payload.server_property_id'=>['nullable','integer','min:1'],
            'payload.proof_needs_reselection'=>['nullable','boolean'],
            'payload.location_accuracy_m'=>['nullable','numeric','between:0,100000'],
            'payload.location_reduced_accuracy'=>['nullable','boolean'],'payload.location_method'=>['nullable','in:gps,manual,unknown'],
            'payload.location_context'=>['nullable','array'],
        ]);
        abort_if(strlen(json_encode($v['payload']))>100000,422);
        $result=DB::transaction(function()use($request,$key,$v){
            $actor=User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $property=isset($v['property_id'])?Property::query()->findOrFail($v['property_id']):null;
            $this->drafts->assertEditable($actor,$property);
            $draft=ListingEditorDraft::query()->where('user_id',$actor->id)->where('client_key',$key)->lockForUpdate()->first();
            if (!$draft) {
                abort_unless($v['expected_revision']===0,409);
                $firstSaved = isset($v['first_saved_at']) ? Carbon::parse($v['first_saved_at'])->utc()->min(now()) : now();
                abort_if($firstSaved->lte(now()->subDays(7)), 410, 'انتهت مدة حفظ المسودة.');
                $draft=new ListingEditorDraft(['user_id'=>$actor->id,'client_key'=>$key,'revision'=>0,'images'=>[],'payload'=>[],'property_id'=>$property?->id]);
                $draft->created_at = $firstSaved;
                $draft->first_saved_us = (int)$firstSaved->format('Uu');
            } else {
                abort_if(($draft->payload['draft_kind'] ?? null)==='retired',410,'ألغي هذا التقدم المؤقت ولا يمكن إعادته بطلب قديم.');
                $this->drafts->assertNotExpired($draft);
                abort_if($property && $draft->property_id !== null && (int)$property->id !== $draft->property_id,409);
                if ($draft->property_id && !$property) {
                    $property = Property::query()->findOrFail($draft->property_id);
                    $this->drafts->assertEditable($actor, $property);
                }
                $incoming=$this->drafts->clean($v['payload']);
                if (($draft->payload['draft_kind'] ?? null)==='saved') $incoming['draft_kind']='saved';
                if (isset($incoming['checkpoint_key']) && ($draft->payload['checkpoint_key'] ?? null)===$incoming['checkpoint_key']) {
                    abort_unless($this->drafts->reviewSaiConsent($draft->payload) == $incoming,409,'مفتاح الحفظ مستخدم لتعديل مختلف.');
                    return $draft;
                }
                $this->drafts->assertRevision($draft,$v['expected_revision']);
            }
            $currency = $v['payload']['currency'] ?? null;
            $storedCurrency = $draft->payload['currency'] ?? $property?->currency ?? 'YER';
            abort_if($currency === null && $storedCurrency !== 'YER', 409, 'حدّث التطبيق لتعديل هذه المسودة بعملة سعرها المحفوظة.');
            if ($currency !== null && !in_array($currency, ['YER', 'SAR', 'USD'], true) && $currency !== $property?->currency) {
                throw ValidationException::withMessages(['payload.currency'=>['اختر عملة سعر متاحة.']]);
            }
            $clean=$this->drafts->clean($v['payload']);
            // Explicitly saved and unclassified legacy work cannot be downgraded
            // by an old editor, including a delayed save from another device.
            if ($draft->exists && (($draft->payload['draft_kind'] ?? null)==='saved' ||
                (($clean['draft_kind'] ?? null)==='recovery' && !$this->drafts->isRecovery($draft)))) $clean['draft_kind']='saved';
            if ($property || $draft->property_id) $clean['draft_kind']='saved';
            foreach ($clean['image_order'] as $token) if (str_starts_with($token,'property-')) {
                $propertyId=$property?->id ?? $draft->property_id;
                abort_unless($propertyId && \App\Models\PropertyImage::query()->where('property_id',$propertyId)->whereKey((int)substr($token,9))->exists(),422,'الصورة لا تنتمي لهذا الإعلان.');
            }
            if (($clean['draft_kind'] ?? null) === 'recovery' && (int)($clean['editor_version'] ?? 0) >= 10) {
                abort_if($this->drafts->progress($clean) <= 50, 422, 'يبدأ الحفظ التلقائي بعد إكمال أكثر من نصف البيانات.');
                $started = (int)$this->drafts->firstSavedAt($draft)->format('Uu');
                abort_if($actor->draft_restart_us && $started <= $actor->draft_restart_us, 410, 'أُلغي هذا التقدم عند بدء إعلان جديد.');
                foreach ($this->drafts->recoveries($actor)->where('client_key','!=',$key)->lockForUpdate()->get() as $other) {
                    if (!$this->drafts->isRecovery($other)) continue;
                    abort_if((int)$this->drafts->firstSavedAt($other)->format('Uu') > $started, 410, 'لديك تقدم تلقائي أحدث.');
                    $this->drafts->retire($other);
                }
            }
            $draft->payload=$clean;
            if ($property) $draft->property_id=$property->id;
            $draft->revision++;$draft->save();return $draft;
        });
        return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function restart(Request $request)
    {
        $input = $request->validate(['started_at'=>['required','date']]);
        $cutoff = (int)Carbon::parse($input['started_at'])->utc()->min(now())->format('Uu');
        DB::transaction(function () use ($request, $cutoff): void {
            $user = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $this->drafts->assertEditable($user);
            $cutoff = max((int)$user->draft_restart_us, $cutoff);
            $user->forceFill(['draft_restart_us'=>$cutoff])->save();
            foreach ($this->drafts->recoveries($user)->lockForUpdate()->get() as $draft) {
                if ($this->drafts->isRecovery($draft) && (int)$this->drafts->firstSavedAt($draft)->format('Uu') <= $cutoff) {
                    $this->drafts->retire($draft);
                }
            }
        });
        return response()->json(['message'=>'يمكنك بدء إعلان جديد.']);
    }

    public function upload(Request $request,string $key,string $imageKey,ListingImageService $storage)
    {
        abort_unless(Str::isUuid($imageKey),404);
        $request->validate(['image'=>['required','file','image','mimes:jpg,jpeg,png,webp','max:8192'],'expected_revision'=>['required','integer','min:0']]);
        $path=null;
        try {$result=DB::transaction(function()use($request,$key,$imageKey,$storage,&$path){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $draft=$this->drafts->owned($request->user(),$key,true);
            $this->drafts->assertEditable($request->user(),$draft->property_id?Property::query()->findOrFail($draft->property_id):null);
            $images=$draft->images;if(isset($images[$imageKey])) {
                abort_unless($storage->matches($request->file('image'),$images[$imageKey]),409,'مفتاح الصورة مستخدم لملف مختلف.');
                return $draft;
            }
            if (($draft->payload['media_version'] ?? 0) === 1) abort_unless(in_array($imageKey,$draft->payload['image_order'] ?? [],true),409,'أزيلت هذه الصورة من المسودة.');
            $this->drafts->assertRevision($draft,$request->integer('expected_revision'));
            abort_if(count($images)>=12,422);
            $queues = app(\App\Services\BackgroundQueue::class);
            $cardFirst = $queues->enabled('images');
            $path=$storage->store($request->file('image'),'editor-drafts/'.$request->user()->id.'/'.$key,$imageKey,$cardFirst);
            $images[$imageKey]=$path;$draft->images=$images;$draft->revision++;$draft->save();
            if ($cardFirst && ! $queues->submit('images', new \App\Jobs\PrepareListingImage($draft->id, hash('sha256', $path), $imageKey))) {
                $storage->prepareVariants($path);
            }
            return $draft;
        });}catch(\Throwable $e){if($path)$storage->removeIfUnused($path);throw $e;}
        return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function image(Request $request,string $key,string $imageKey,ListingImageService $storage)
    {
        $draft=$this->drafts->owned($request->user(),$key);$path=$draft->images[$imageKey] ?? null;abort_unless($path,404);
        return $storage->response($path,(string)$request->query('variant','card'));
    }

    public function removeImage(Request $request,string $key,string $imageKey)
    {
        $request->validate(['expected_revision'=>['required','integer','min:0']]);$path=null;
        $result=DB::transaction(function()use($request,$key,$imageKey,&$path){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);$draft=$this->drafts->owned($request->user(),$key,true);
            $this->drafts->assertEditable($request->user(),$draft->property_id?Property::query()->findOrFail($draft->property_id):null);
            $images=$draft->images;if(!isset($images[$imageKey])) return $draft;
            $this->drafts->assertRevision($draft,$request->integer('expected_revision'));
            $path=$images[$imageKey];unset($images[$imageKey]);$draft->images=$images;$draft->revision++;$draft->save();return $draft;
        });
        if($path)$this->drafts->removeFiles([$path]);return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function destroy(Request $request,string $key)
    {
        if ($request->boolean('recovery_only')) {
            $v=$request->validate(['expected_revision'=>['required','integer','min:0']]);
            abort_unless(Str::isUuid($key),404);
            $paths=DB::transaction(function()use($request,$key,$v){
                $actor=User::query()->lockForUpdate()->findOrFail($request->user()->id);
                $this->drafts->assertEditable($actor);
                $draft=ListingEditorDraft::query()->where('user_id',$actor->id)->where('client_key',$key)->lockForUpdate()->first();
                if (!$draft) {
                    abort_if(ListingEditorDraft::query()->where('client_key',$key)->exists(),404);
                    abort_unless($v['expected_revision']===0,409);
                    $draft=new ListingEditorDraft(['user_id'=>$actor->id,'client_key'=>$key,'revision'=>0,'images'=>[],'payload'=>[]]);
                } elseif (($draft->payload['draft_kind'] ?? null)==='retired') {
                    return (array)($draft->payload['cleanup_paths'] ?? []);
                } else {
                    abort_unless($this->drafts->isRecovery($draft),409,'هذه مسودة محفوظة؛ لن تُحذف عند بدء إعلان جديد.');
                    $this->drafts->assertRevision($draft,$v['expected_revision']);
                }
                $paths=array_values($draft->images ?? []);
                // Retain only a small revision tombstone, never the private data.
                // This fences an in-flight revision-zero save even before it arrives.
                $draft->payload=['editor_version'=>10,'draft_kind'=>'retired','image_order'=>[],'fields'=>[], 'cleanup_paths'=>$paths];
                $draft->images=[];$draft->property_id=null;$draft->revision++;$draft->save();
                return $paths;
            });
            foreach ($paths as $path) app(ListingImageService::class)->removeIfUnused($path,true);
            DB::transaction(function()use($request,$key){
                $draft=ListingEditorDraft::query()->where('user_id',$request->user()->id)->where('client_key',$key)->lockForUpdate()->firstOrFail();
                $payload=$draft->payload;unset($payload['cleanup_paths']);$draft->payload=$payload;$draft->save();
            });
            return response()->json(['message'=>'أُلغي التقدم المؤقت.']);
        }
        $paths=DB::transaction(function()use($request,$key){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);$draft=$this->drafts->owned($request->user(),$key,true);
            if($draft->property_id){$property=Property::query()->lockForUpdate()->find($draft->property_id);
                if($property && $property->status==='draft'){$this->drafts->assertEditable($request->user(),$property);
                    app(PropertyIdentityService::class)->releaseRepresentationForListing($property,'editor_draft_deleted');$property->status='archived';$property->save();}}
            $paths=array_values($draft->images);$draft->delete();return $paths;
        });
        $this->drafts->removeFiles($paths);return response()->json(['message'=>'حذفت المسودة.']);
    }
}
