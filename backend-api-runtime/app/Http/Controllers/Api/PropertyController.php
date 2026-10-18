<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\ListingDocument;
use App\Models\AdvertiserRating;
use App\Models\ListingComment;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\RegionService;
use App\Services\ListingWorkflowService;
use App\Services\PropertyAssetService;
use App\Services\PropertyIdentityService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use Throwable;

class PropertyController extends Controller
{
    private const TYPES = ['apartment', 'floor', 'building', 'house', 'villa', 'land', 'shop', 'office', 'farm'];
    private const PURPOSES = ['sale', 'rent'];
    private const TENURE_TYPES = ['freehold', 'waqf'];
    private const SALE_TENURE_PROPERTY_TYPES = ['apartment', 'floor', 'building', 'house', 'villa', 'land', 'farm'];
    private const AREA_UNITS = [
        'sqm' => 1.0,
        'libna_sanaani' => 44.44,
        'libna_dhamari' => 114.49,
        'qasaba_taizi_ashari' => 20.25,
        'qasaba_taizi_hadawi' => 29.16,
        'qasaba_ibbi' => 56.25,
    ];
    private const FACADES = ['north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest', 'multiple'];
    private const RESIDENTIAL_TYPES = ['apartment', 'floor', 'house', 'villa'];
    private const STRUCTURE_TYPES = ['apartment', 'floor', 'building', 'house', 'villa', 'shop', 'office'];

    public function __construct(
        private readonly ApiTokenService $tokens,
        private readonly AuditLogService $audit,
        private readonly CloudAssetStorageService $storage,
        private readonly RegionService $regions,
        private readonly PropertyAssetService $assets,
        private readonly PropertyIdentityService $identity,
        private readonly ListingWorkflowService $workflow,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $validated = $request->validate($this->filterRules());
        $perPage = max(1, min((int) ($request->input('per_page', 20)), 50));

        $query = $this->publicQuery();
        $this->applyFilters($query, $validated);
        $this->validateBounds($validated);
        app(\App\Services\PropertyDiscoveryFilterService::class)->applyGeometry($query, $validated);

        $sort = (string) $request->input('sort', 'latest');
        match ($sort) {
            'price_asc' => $query->orderBy('price')->orderByDesc('id'),
            'price_desc' => $query->orderByDesc('price')->orderByDesc('id'),
            default => $query->latest('id'),
        };

        $page = $query->paginate($perPage);

        return response()->json([
            'data' => collect($page->items())
                ->map(fn (Property $property) => $this->summaryData($property, $request))
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function nearby(Request $request): JsonResponse
    {
        $validated = $request->validate(array_merge($this->filterRules(), [
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'radius_km' => ['nullable', 'numeric', 'min:0.1', 'max:100'],
            'south' => ['nullable', 'numeric', 'between:-90,90'],
            'west' => ['nullable', 'numeric', 'between:-180,180'],
            'north' => ['nullable', 'numeric', 'between:-90,90'],
            'east' => ['nullable', 'numeric', 'between:-180,180'],
        ]));

        $latitude = (float) $validated['latitude'];
        $longitude = (float) $validated['longitude'];
        $radiusKm = (float) ($validated['radius_km'] ?? 30);
        $validated['radius_km'] = $radiusKm;

        $this->validateBounds($validated);

        $query = $this->publicQuery();
        $this->applyFilters($query, $validated);
        app(\App\Services\PropertyDiscoveryFilterService::class)->applyPolygonForNearby($query, $validated);

        if (DB::connection()->getDriverName() === 'pgsql') {
            $pointSql = 'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography';
            $distanceSql = "ST_Distance(location, {$pointSql})";

            $properties = $query
                ->select('properties.*')
                ->selectRaw("{$distanceSql} AS distance_m", [$longitude, $latitude])
                ->whereNotNull('location')
                ->whereRaw(
                    "ST_DWithin(location, {$pointSql}, ?)",
                    [$longitude, $latitude, $radiusKm * 1000],
                )
                ->orderBy('distance_m')
                ->orderByDesc('id')
                ->limit(250)
                ->get()
                ->map(fn (Property $property) => array_merge(
                    $this->summaryData($property, $request),
                    ['distance_km' => round(((float) $property->distance_m) / 1000, 2)],
                ))
                ->values();

            return response()->json(['data' => $properties]);
        }

        // SQLite is used only by the automated test suite. Production uses the
        // PostGIS branch above so the spatial index remains effective at scale.
        $properties = $query->limit(1000)->get()
            ->map(function (Property $property) use ($latitude, $longitude, $request) {
                $distanceKm = $this->distanceKm(
                    $latitude,
                    $longitude,
                    (float) $property->latitude,
                    (float) $property->longitude,
                );

                return array_merge($this->summaryData($property, $request), [
                    'distance_km' => round($distanceKm, 2),
                ]);
            })
            ->filter(fn (array $property) => $property['distance_km'] <= $radiusKm)
            ->sortBy('distance_km')
            ->values()
            ->take(250);

        return response()->json(['data' => $properties]);
    }

    public function marketplace(Request $request): JsonResponse
    {
        $v = $request->validate(['type' => ['nullable', Rule::in(self::TYPES)],
            'governorate' => ['nullable', 'string', 'max:120'],
            'latitude' => ['nullable', 'required_with:longitude', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'required_with:latitude', 'numeric', 'between:-180,180']]);
        $context = app(\App\Services\MarketplaceContextService::class)->resolve($v);
        $base = $this->publicQuery();
        $this->applyFilters($base, ['type' => $v['type'] ?? null, 'governorate' => $context['governorate']]);
        $sections = [];
        foreach (['spotlight', 'latest', 'sale', 'rent'] as $section) {
            $query = clone $base;
            if ($section === 'spotlight') $query->where('spotlight_until', '>', now());
            if (in_array($section, ['sale', 'rent'], true)) $query->where('purpose', $section);
            $sections[$section] = $query->latest('id')->limit(6)->get()->map(fn ($p) => $this->summaryData($p, $request))->values()->all();
        }
        if (isset($v['latitude'],$v['longitude'])) {
            $nearby=$this->publicQuery();$this->applyFilters($nearby,['type'=>$v['type'] ?? null]);$lat=(float)$v['latitude'];$lon=(float)$v['longitude'];
            if(DB::getDriverName()==='pgsql'){
                $point='ST_SetSRID(ST_MakePoint(?, ?),4326)::geography';
                $nearby->whereRaw("ST_DWithin(location::geography, $point, ?)",[$lon,$lat,30000])
                    ->orderByRaw("ST_Distance(location::geography, $point)",[$lon,$lat]);
                $nearbyRows=$nearby->limit(6)->get();
            }else{
                $nearbyRows=$nearby->limit(1000)->get()->filter(fn($p)=>$this->distanceKm($lat,$lon,(float)$p->latitude,(float)$p->longitude)<=30)
                    ->sortBy(fn($p)=>$this->distanceKm($lat,$lon,(float)$p->latitude,(float)$p->longitude))->take(6);
            }
            $sections['nearby']=$nearbyRows->map(fn($p)=>$this->summaryData($p,$request))->values()->all();
        }
        $purposeOrder=count($sections['rent'])>count($sections['sale'])?['rent','sale']:['sale','rent'];
        $sectionOrder=array_values(array_filter(array_merge(['nearby','spotlight','latest'],$purposeOrder),fn($key)=>!empty($sections[$key])));
        $ranking = app(\App\Services\BrokerRankingService::class);
        $localNames = $context['governorate'] === 'صنعاء' ? ['صنعاء', 'أمانة العاصمة'] : [$context['governorate']];
        $localOwnerIds = (clone $base)->select('properties.user_id');
        $brokers = $ranking->query($context['governorate'])->where(function ($q) use ($context, $localNames, $localOwnerIds): void {
            $q->whereHas('accountVerificationProfile', fn ($profile) => $profile
                ->whereIn('details->governorate', $localNames)
                ->orWhereJsonContains('details->work_areas', $context['governorate']))
                ->orWhereIn('users.id', $localOwnerIds);
        })->limit(5)->get()->map(fn ($u) => $ranking->publicData($u))->values();
        return response()->json(['data' => ['context' => $context, 'sections' => $sections, 'section_order'=>$sectionOrder, 'brokers' => $brokers]]);
    }

    public function marketplaceLocations(): JsonResponse
    {
        return response()->json(['data' => app(\App\Services\MarketplaceContextService::class)->locations()]);
    }

    public function show(Request $request, Property $property): JsonResponse
    {
        $user = $this->tokens->authenticate($request, false);
        $isOwner = $user !== null && (int) $property->user_id === (int) $user->id;
        abort_unless($property->isPubliclyAvailable() || $isOwner, 404);

        $property->load('images');

        $similar = $this->publicQuery()
            ->where('id', '!=', $property->id)
            ->where('type', $property->type)
            ->orderByRaw('ABS(price - ?) asc', [(float) $property->price])
            ->limit(6)
            ->get()
            ->map(fn (Property $item) => $this->summaryData($item, $request))
            ->values();

        return response()->json([
            'data' => array_merge($this->detailData($property, $request), [
                'is_owner' => $isOwner,
                'similar' => $similar,
            ]),
        ]);
    }

    public function mine(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $perPage = max(1, min((int) $request->input('per_page', 20), 50));

        $workspaceView = $request->input('view') === 'workspace';
        $page = Property::query()
            ->with($workspaceView ? ['images', 'documents'] : ['images'])
            ->where('user_id', $user->id)
            ->latest('id')
            ->paginate($perPage);

        if ($workspaceView) {
            $ids=collect($page->items())->pluck('id');
            $favorites=DB::table('property_favorites')->whereIn('property_id',$ids)->groupBy('property_id')->selectRaw('property_id, COUNT(*) AS total')->pluck('total','property_id');
            $conversations=DB::table('message_threads')->whereIn('property_id',$ids)->groupBy('property_id')->selectRaw('property_id, COUNT(*) AS total')->pluck('total','property_id');
            $viewings=DB::table('viewing_bookings')->where('target_type','property')->whereIn('target_id',$ids)->groupBy('target_id')->selectRaw('target_id, COUNT(*) AS total')->pluck('total','target_id');
            foreach ($page->items() as $property) {
                $property->setAttribute('favorite_count',(int)$favorites->get($property->id,0));
                $property->setAttribute('conversation_count',(int)$conversations->get($property->id,0));
                $property->setAttribute('viewing_count',(int)$viewings->get($property->id,0));
            }
        }

        return response()->json([
            'data' => collect($page->items())
                ->map(fn (Property $property) => $workspaceView
                    ? $this->mineWorkspaceData($property, $request)
                    : $this->detailData($property, $request))
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function listingAccess(Request $request): JsonResponse
    {
        return response()->json(['data' => app(\App\Services\ListingAccessService::class)->metadata($request->user())]);
    }

    public function store(Request $request): JsonResponse
    {
        /** @var User $user */
        $user=$request->user();$this->assertAdvertiserCanCreateDraft($user);
        $request->validate(['editor_draft_key'=>['nullable','uuid']]);
        if ($request->input('editor_draft_key')) {
            $draft=app(\App\Services\ListingEditorDraftService::class)->owned($user,$request->input('editor_draft_key'));
            if ($draft->property_id) return $this->update($request,Property::query()->findOrFail($draft->property_id));
        }
        app(\App\Services\ListingAccessService::class)->assertCanCreate($user,$request->input('editor_draft_key'));$validated=$request->validate($this->listingRules(false));
        $validated=$this->normalizeListingFields($validated,null,false);
        $this->assertV2ListingCompleteness($validated);
        $cell=$this->regions->assertListingAllowed($user,(float)$validated['latitude'],(float)$validated['longitude']);
        $asset=$this->identity->resolveOrCreateAsset($user,$validated);
        $this->assets->assertPurposeNotBlocked($asset,(string)$validated['purpose']);
        $storedPublic=[];$storedPrivate=[];
        try{
            $property=DB::transaction(function()use($request,$validated,$user,$cell,$asset,&$storedPublic,&$storedPrivate){
                $lockedUser=User::query()->lockForUpdate()->findOrFail($user->id);
                app(\App\Services\ListingAccessService::class)->assertCanCreate($lockedUser,$request->input('editor_draft_key'));
                $property=Property::query()->create(array_merge($this->listingPayload($validated,false),['user_id'=>$user->id,'property_asset_id'=>$asset->id,'geo_cell_id'=>$cell?->id,'owner_key'=>null,'status'=>'draft','review_status'=>'draft']));
                $this->syncLocation($property);$this->storeImages($request,$property,0,$storedPublic);app(\App\Services\ListingEditorDraftService::class)->attach($request,$property);$this->storeProofDocuments($request,$property,$user,$storedPrivate);
                $this->audit->record($user,'listing.created',$property,['purpose'=>$property->purpose,'status'=>'draft','property_asset_id'=>$asset->id],$request,$user->id);
                return $property->fresh(['images','documents','propertyAsset']);
            });
        }catch(Throwable $e){$this->deletePaths($storedPublic);$this->deletePrivatePaths($storedPrivate);throw $e;}
        if ($request->boolean('submit_for_review')) {
            $property = $this->workflow->submit($user, $property, $request);
            return response()->json(['message'=>'Listing submitted for support review.','data'=>$this->detailData($property,$request)],201);
        }
        return response()->json(['message'=>'Draft listing created. Submit it for support review when ready.','data'=>$this->detailData($property,$request)],201);
    }

    public function update(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertOwner($property,$user);$this->assertAdvertiserCanCreateDraft($user);
        if(in_array($property->review_status,['submitted','under_review','rejected_blocked'],true)) abort(409,'This listing cannot be edited in its current review state.');
        $validated=$request->validate($this->listingRules(true));$validated=$this->normalizeListingFields($validated,$property,true);$this->assertV2ListingCompleteness(array_merge($this->listingState($property),$validated));$replaceImages=$request->boolean('replace_images');$incomingCount=count($request->file('images',[]));$existingCount=$property->images()->count();
        if(!$replaceImages&&$existingCount+$incomingCount>12)throw ValidationException::withMessages(['images'=>['A listing may contain at most 12 images.']]);
        if($property->documents()->count()+count($request->file('proof_documents',[]))>5)throw ValidationException::withMessages(['proof_documents'=>['A listing may contain at most 5 proof documents.']]);
        $storedPublic=[];$storedPrivate=[];$oldImages=$replaceImages?$property->images()->get():collect();
        try{$property=DB::transaction(function()use($request,$property,$validated,$replaceImages,$user,&$storedPublic,&$storedPrivate){
            User::query()->lockForUpdate()->findOrFail($user->id);$property=Property::query()->lockForUpdate()->findOrFail($property->id);
            abort_if($property->status === 'archived' || in_array($property->review_status,['submitted','under_review','rejected_blocked'],true),409);
            $wasPublished=$property->status==='published';$property->fill($this->listingPayload($validated,true));
            $cell=$this->regions->assertListingAllowed($user,(float)$property->latitude,(float)$property->longitude);$property->geo_cell_id=$cell?->id;
            $identity=array_merge(['purpose'=>$property->purpose,'type'=>$property->type,'latitude'=>$property->latitude,'longitude'=>$property->longitude,'area_m2'=>$property->area_m2,'bedrooms'=>$property->bedrooms,'bathrooms'=>$property->bathrooms,'address'=>$property->address],$validated);
            if ((int) $property->listing_input_version >= 6) $identity = array_merge($this->listingState($property), $validated);
            $asset=$this->identity->resolveOrCreateAsset($user,$identity,$property->propertyAsset);$property->property_asset_id=$asset->id;
            $property->status='draft';$property->review_status='draft';$property->submitted_at=null;$property->reviewed_at=null;$property->last_review_reason=null;if($wasPublished)$property->published_at=null;$property->save();$this->syncLocation($property);
            if($replaceImages)$property->images()->delete();if($request->hasFile('images'))$this->storeImages($request,$property,$property->images()->count(),$storedPublic);$this->storeProofDocuments($request,$property,$user,$storedPrivate);app(\App\Services\ListingEditorDraftService::class)->attach($request,$property);
            $this->audit->record($user,$wasPublished?'listing.published_edit_moved_to_draft':'listing.updated',$property,['changed_fields'=>array_values(array_keys($validated)),'replace_images'=>$replaceImages,'property_asset_id'=>$asset->id],$request,$user->id);
            return $property->fresh(['images','documents','propertyAsset']);
        });}catch(Throwable $e){$this->deletePaths($storedPublic);$this->deletePrivatePaths($storedPrivate);throw $e;}
        if($replaceImages)$this->deleteImageFiles($oldImages);
        if ($request->boolean('submit_for_review')) {
            $property = $this->workflow->submit($user, $property, $request);
            return response()->json(['message'=>'Listing updates submitted for support review.','data'=>$this->detailData($property,$request)]);
        }
        return response()->json(['message'=>'Listing saved as draft and requires review before publication.','data'=>$this->detailData($property,$request)]);
    }

    public function destroy(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertOwner($property,$user);
        if(in_array($property->review_status,['submitted','under_review','rejected_blocked'],true)) abort(409,'This listing cannot be deleted in its current review state.');
        $images=$property->images()->get();$docs=$property->documents()->get();
        DB::transaction(function()use($property,$user,$request):void{$this->identity->releaseRepresentationForListing($property);$property->delete();$this->audit->record($user,'listing.deleted',$property,['property_asset_id'=>$property->property_asset_id],$request,$user->id);});
        $this->deleteImageFiles($images);$this->deleteProofFiles($docs);return response()->json(['message'=>'Listing deleted.']);
    }

    public function submit(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertOwner($property,$user);$property=$this->workflow->submit($user,$property,$request);return response()->json(['message'=>'Listing submitted for support review.','data'=>$this->detailData($property,$request)]);
    }

    public function uploadProofDocuments(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertOwner($property,$user);if(in_array($property->review_status,['submitted','under_review','rejected_blocked'],true))abort(409,'Proof documents cannot be changed in the current review state.');
        $request->validate(['proof_documents'=>['required','array','min:1','max:5'],'proof_documents.*'=>['file','image','mimes:jpg,jpeg,png,webp','max:10240']]);if($property->documents()->count()+count($request->file('proof_documents',[]))>5)throw ValidationException::withMessages(['proof_documents'=>['A listing may contain at most 5 proof documents.']]);
        $paths=[];try{DB::transaction(function()use($request,$property,$user,&$paths){$this->storeProofDocuments($request,$property,$user,$paths);$this->audit->record($user,'listing.proof_documents_added',$property,['count'=>count($paths)],$request,$user->id);});}catch(Throwable $e){$this->deletePrivatePaths($paths);throw $e;}
        return response()->json(['message'=>'Proof documents uploaded.','data'=>$this->detailData($property->fresh(['images','documents','propertyAsset']),$request)]);
    }

    public function deleteProofDocument(Request $request, Property $property, ListingDocument $document): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertOwner($property,$user);abort_unless((int)$document->property_id===(int)$property->id,404);if(in_array($property->review_status,['submitted','under_review','rejected_blocked'],true))abort(409,'Proof documents cannot be changed in the current review state.');$path=$document->path;$document->delete();$this->storage->deletePrivate($path);$this->audit->record($user,'listing.proof_document_deleted',$property,[],$request,$user->id);return response()->json(['message'=>'Proof document deleted.']);
    }

    public function media(Request $request, PropertyImage $image)
    {
        $image->loadMissing('property');
        $property = $image->property;
        abort_unless($property, 404);

        $user = $this->tokens->authenticate($request, false);
        $isOwner = $user !== null && (int) $property->user_id === (int) $user->id;
        $isReviewer = $user !== null && $user->hasPermission('listings.moderate');

        abort_unless($property->status === 'published' || $isOwner || $isReviewer, 404);
        abort_if($image->cdn_url, 404);
        if (str_starts_with($image->path,'editor-drafts/')) {
            abort_unless($this->storage->existsPrivate($image->path),404);
            return $this->storage->responsePrivate($image->path,null,['Cache-Control'=>$property->status==='published'?'public, max-age=86400':'private, no-store']);
        }
        abort_unless($this->storage->existsPublic($image->path), 404);

        return $this->storage->responsePublic($image->path, null, [
            'Cache-Control' => 'public, max-age=86400',
        ]);
    }

    private function filterRules(): array
    {
        return app(\App\Services\PropertyDiscoveryFilterService::class)->rules();
    }

    private function listingRules(bool $partial): array
    {
        $required = $partial ? ['sometimes'] : ['required'];

        return [
            'title' => array_merge($required, ['string', 'max:160']),
            'description' => ['nullable', 'string', 'max:5000'],
            'purpose' => array_merge($required, [Rule::in(self::PURPOSES)]),
            'type' => array_merge($required, [Rule::in(self::TYPES)]),
            'tenure_type' => ['nullable', 'string', Rule::in(self::TENURE_TYPES)],
            'price' => array_merge($required, ['numeric', 'min:0', 'max:9999999999999']),
            'currency' => ['sometimes', 'string', 'size:3'],
            'listing_input_version' => ['nullable', 'integer', Rule::in([1, 2, 3, 4, 5, 6, 7, 8])],
            'rental_conditions' => ['nullable'],
            'editor_draft_key' => ['nullable','uuid'],
            'editor_draft_revision' => ['required_with:editor_draft_key','integer','min:1'],
            'area_m2' => ['nullable', 'integer', 'min:1', 'max:10000000'],
            'area_value' => ['nullable', 'numeric', 'gt:0', 'max:10000000'],
            'area_unit' => ['nullable', 'string', Rule::in(array_keys(self::AREA_UNITS))],
            'bedrooms' => ['nullable', 'integer', 'min:0', 'max:100'],
            'bathrooms' => ['nullable', 'integer', 'min:0', 'max:100'],
            'has_parking' => ['nullable', 'boolean'],
            'has_elevator' => ['nullable', 'boolean'],
            'building_facade' => ['nullable', 'string', Rule::in(self::FACADES)],
            'address' => ['nullable', 'string', 'max:255'],
            'building_reference' => ['nullable', 'string', 'max:160'],
            'unit_number' => ['nullable', 'string', 'max:64'],
            'floor_number' => ['nullable', 'string', 'max:32'],
            'unit_occupies_entire_floor' => ['sometimes', 'boolean'],
            'land_boundary_geojson' => ['nullable'],
            'latitude' => array_merge($required, ['numeric', 'between:-90,90']),
            'longitude' => array_merge($required, ['numeric', 'between:-180,180']),
            'contact_phone' => ['nullable', 'string', 'max:32'],
            'contact_whatsapp' => ['nullable', 'string', 'max:32'],
            'ownership_document_type' => ['nullable', 'string', Rule::in(['purchase_deed','registry_record','partition_deed','court_judgment','inheritance_document','ownership_contract','other'])],
            'document_owner_name' => ['nullable', 'string', 'max:160'],
            'owner_relationship_type' => ['nullable', 'string', Rule::in(['owner','agent','heir','co_owner','other'])],
            'owner_relationship_note' => ['nullable', 'string', 'max:255'],
            'replace_images' => ['nullable', 'boolean'],
            'submit_for_review' => ['nullable', 'boolean'],
            'images' => ['nullable', 'array', 'max:12'],
            'images.*' => ['file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:8192'],
            'proof_documents' => ['nullable', 'array', 'max:5'],
            'proof_documents.*' => ['file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'owner_id_front' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'owner_id_back' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'owner_selfie' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'ownership_proof' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ];
    }

    private function listingPayload(array $validated, bool $partial): array
    {
        $allowed = [
            'listing_input_version', 'rental_conditions', 'title', 'description', 'purpose', 'type', 'tenure_type', 'price', 'currency',
            'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'has_elevator', 'building_facade', 'address', 'latitude', 'longitude',
            'building_reference', 'unit_number', 'floor_number', 'unit_occupies_entire_floor', 'land_boundary_geojson',
            'contact_phone', 'contact_whatsapp',
            'ownership_document_type', 'document_owner_name', 'owner_relationship_type', 'owner_relationship_note',
        ];

        $payload = [];
        foreach ($allowed as $field) {
            if (array_key_exists($field, $validated)) {
                $payload[$field] = $validated[$field];
            }
        }
        if (array_key_exists('currency', $payload)) {
            $payload['currency'] = strtoupper((string) $payload['currency']);
        } elseif (! $partial) {
            $payload['currency'] = 'YER';
        }

        if (($payload['type'] ?? null) === 'land') {
            $payload['bedrooms'] = null;
            $payload['bathrooms'] = null;
            $payload['building_reference'] = null;
            $payload['unit_number'] = null;
            $payload['floor_number'] = null;
        } elseif (! in_array(($payload['type'] ?? null), ['apartment','floor','office','shop'], true)) {
            $payload['building_reference'] = null;
            $payload['unit_number'] = null;
            $payload['floor_number'] = null;
            $payload['land_boundary_geojson'] = null;
        } else {
            $payload['land_boundary_geojson'] = null;
        }

        if (($payload['type'] ?? null) === 'floor') $payload['unit_number'] = null;
        return $payload;
    }

    private function normalizeListingFields(array $validated, ?Property $existing, bool $partial): array
    {
        $purpose = (string) ($validated['purpose'] ?? $existing?->purpose ?? '');
        $type = (string) ($validated['type'] ?? $existing?->type ?? '');
        $version = (int) ($validated['listing_input_version'] ?? $existing?->listing_input_version ?? 1);
        if ($version >= 8) {
            $checked = app(\App\Services\DynamicPropertySchema::class)->validateApartmentFloor($validated + ['type'=>$type]);
            if (isset($checked['floor_number'])) $validated['floor_number'] = $checked['floor_number'];
        }
        if ($partial && $existing && $version >= 6) {
            $state = $this->listingState($existing);
            foreach (['listing_input_version','type','building_reference','unit_number','floor_number','land_boundary_geojson'] as $key) {
                if (! array_key_exists($key, $validated)) $validated[$key] = $state[$key];
            }
        }
        // An optional position field must not erase a known historical unit.
        if ($version >= 7 && $purpose === 'rent' && $type === 'apartment'
            && $existing?->type === 'apartment' && trim((string) $existing?->unit_number) !== ''
            && trim((string) ($validated['unit_number'] ?? '')) === '') {
            $validated['unit_number'] = $existing->unit_number;
        }
        if (array_key_exists('rental_conditions', $validated)) {
            $conditions = app(\App\Services\RentalConditionService::class)->normalize($validated['rental_conditions'] ?? []);
            if ($purpose !== 'rent' && $conditions !== []) throw ValidationException::withMessages(['rental_conditions' => ['شروط الإيجار متاحة لإعلانات الإيجار فقط.']]);
            $validated['rental_conditions'] = $conditions;
        } elseif ($purpose !== 'rent') $validated['rental_conditions'] = [];
        if ($version >= 6 && ($type === 'floor' || ($type === 'apartment' && ($validated['unit_occupies_entire_floor'] ?? false)))
            && ! ($existing && ($existing->type === 'floor' || $existing->unit_occupies_entire_floor))) {
            throw ValidationException::withMessages(['unit_occupies_entire_floor' => ['حدد الشقة برقمها أو موضعها؛ نطاق الدور القديم محفوظ للإعلانات السابقة فقط.']]);
        }
        if ($version >= 6 && $purpose === 'rent' && $type === 'apartment' && array_key_exists('area_value', $validated) && $validated['area_value'] === null) {
            $validated['area_value'] = null; $validated['area_m2'] = null; $validated['area_unit'] = null;
            $withoutArea = true;
        } else $withoutArea = false;
        if ($version >= 8 && $type === 'shop' && isset($validated['area_unit']) && $validated['area_unit'] !== 'sqm') throw ValidationException::withMessages(['area_unit'=>['مساحة المحل بالمتر المربع.']]);
        $hasAreaInput = array_key_exists('area_value', $validated) || array_key_exists('area_unit', $validated);
        $hasLegacyArea = array_key_exists('area_m2', $validated);

        if ($hasAreaInput && ! $withoutArea) {
            $areaValue = array_key_exists('area_value', $validated)
                ? (float) $validated['area_value']
                : (float) ($existing?->area_value ?? $existing?->area_m2 ?? 0);
            $areaUnit = array_key_exists('area_unit', $validated)
                ? (string) $validated['area_unit']
                : (string) ($existing?->area_unit ?? 'sqm');

            if ($areaValue <= 0 || ! array_key_exists($areaUnit, self::AREA_UNITS)) {
                throw ValidationException::withMessages([
                    'area_value' => ['Area value and unit must be valid.'],
                ]);
            }

            $validated['area_value'] = round($areaValue, 2);
            $validated['area_unit'] = $areaUnit;
            $validated['area_m2'] = max(1, (int) round($areaValue * self::AREA_UNITS[$areaUnit]));
        } elseif ($hasLegacyArea && ! $withoutArea) {
            $validated['area_value'] = (float) $validated['area_m2'];
            $validated['area_unit'] = 'sqm';
        } elseif (! $partial && (($validated['listing_input_version'] ?? 1) === 2)) {
            throw ValidationException::withMessages([
                'area_value' => ['Area is required.'],
            ]);
        }

        $effectivePurpose = (string) ($validated['purpose'] ?? $existing?->purpose ?? '');
        $effectiveType = (string) ($validated['type'] ?? $existing?->type ?? '');
        if ($effectivePurpose !== 'sale' || ! in_array($effectiveType, self::SALE_TENURE_PROPERTY_TYPES, true)) {
            $validated['tenure_type'] = null;
        }

        if ($effectiveType === 'land') {
            $validated['bedrooms'] = null;
            $validated['bathrooms'] = null;
            $validated['has_parking'] = null;
            $validated['building_facade'] = $version >= 6 ? ($validated['building_facade'] ?? $existing?->building_facade) : null;
            $validated['building_reference'] = null;
            $validated['unit_number'] = null;
            $validated['floor_number'] = null;
        } elseif (! in_array($effectiveType, ['apartment','floor','office','shop'], true)) {
            $validated['building_reference'] = null;
            $validated['unit_number'] = null;
            $validated['floor_number'] = null;
            $validated['land_boundary_geojson'] = null;
        } else {
            $validated['land_boundary_geojson'] = null;
        }

        if ((int) ($validated['listing_input_version'] ?? 1) >= 4) {
            if (! in_array($effectiveType, self::RESIDENTIAL_TYPES, true)) {
                $validated['bedrooms'] = null; $validated['bathrooms'] = null;
            }
            if (! in_array($effectiveType, self::STRUCTURE_TYPES, true)) {
                $validated['has_parking'] = null;
                if (! ($version >= 6 && $effectiveType === 'land')) $validated['building_facade'] = null;
            }
        }
        $wholeFloor = $effectiveType === 'floor' || ($effectiveType === 'apartment' && (bool) ($validated['unit_occupies_entire_floor'] ?? $existing?->unit_occupies_entire_floor ?? false));
        if (! in_array($effectiveType, ['apartment', 'floor', 'building', 'office'], true)) $validated['has_elevator'] = null;
        $validated['unit_occupies_entire_floor'] = $effectiveType === 'apartment' && $wholeFloor;
        if ($wholeFloor) $validated['unit_number'] = null;
        if ($effectiveType === 'shop' && (int) ($validated['listing_input_version'] ?? 1) >= 4 && !array_key_exists('floor_number', $validated)) $validated['floor_number'] = null;
        if ($version >= 8) $validated = app(\App\Services\DynamicPropertySchema::class)->facts($validated + ['type'=>$type,'purpose'=>$purpose],true);
        return $validated;
    }

    private function assertV2ListingCompleteness(array $listing): void
    {
        if ((int) ($listing['listing_input_version'] ?? 1) >= 8) {
            $errors=[];
            foreach (array_merge(['address','price'],app(\App\Services\DynamicPropertySchema::class)->required($listing)) as $key) {
                $value=$listing[$key] ?? null;
                if ($value === null || $value === '' || (in_array($key,['price','area_value','bedrooms','bathrooms'],true) && (float)$value <= 0)) $errors[$key][]='أكمل هذه المعلومة المطلوبة.';
            }
            if ($errors) throw ValidationException::withMessages($errors);
            return;
        }
        if (! in_array((int) ($listing['listing_input_version'] ?? 1), [2, 4, 5, 6, 7], true)) {
            return;
        }

        $errors = [];
        if (trim((string) ($listing['address'] ?? '')) === '') {
            $errors['address'][] = 'Address is required for listing input version 2.';
        }
        $optionalArea = (int) ($listing['listing_input_version'] ?? 1) >= 6 && ($listing['type'] ?? '') === 'apartment' && ($listing['purpose'] ?? '') === 'rent';
        if (! $optionalArea && (! isset($listing['area_value']) || (float) $listing['area_value'] <= 0 || empty($listing['area_unit']))) {
            $errors['area_value'][] = 'Area value and unit are required.';
        }
        if (! isset($listing['price']) || (float) $listing['price'] <= 0) {
            $errors['price'][] = 'Price must be greater than zero.';
        }

        $purpose = (string) ($listing['purpose'] ?? '');
        $type = (string) ($listing['type'] ?? '');
        if ($purpose === 'sale' && in_array($type, self::SALE_TENURE_PROPERTY_TYPES, true)) {
            if (! in_array((string) ($listing['tenure_type'] ?? ''), self::TENURE_TYPES, true)) {
                $errors['tenure_type'][] = 'حدد نوع الملكية: حر أو وقف.';
            }
        }

        if (in_array($type, self::RESIDENTIAL_TYPES, true)) {
            if (! isset($listing['bedrooms']) || (int) $listing['bedrooms'] < 1) {
                $errors['bedrooms'][] = 'Bedrooms are required for residential properties.';
            }
            if (! isset($listing['bathrooms']) || (int) $listing['bathrooms'] < 1) {
                $errors['bathrooms'][] = 'Bathrooms are required for residential properties.';
            }
        }
        if (in_array($type, self::STRUCTURE_TYPES, true)) {
            if (! array_key_exists('has_parking', $listing) || $listing['has_parking'] === null) {
                $errors['has_parking'][] = 'Parking availability must be selected.';
            }
            if (empty($listing['building_facade'])) {
                $errors['building_facade'][] = 'Building facade must be selected.';
            }
        }

        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }
    }

    private function listingState(Property $property): array
    {
        return [
            'listing_input_version' => $property->listing_input_version ?? 1,
            'title' => $property->title,
            'description' => $property->description,
            'rental_conditions' => $property->rental_conditions ?? [],
            'purpose' => $property->purpose,
            'type' => $property->type,
            'unit_occupies_entire_floor' => $property->type === 'floor' || (bool) $property->unit_occupies_entire_floor,
            'tenure_type' => $property->tenure_type,
            'price' => $property->price,
            'currency' => $property->currency,
            'area_m2' => $property->area_m2,
            'area_value' => $property->area_value ?? $property->area_m2,
            'area_unit' => $property->area_unit ?? 'sqm',
            'bedrooms' => $property->bedrooms,
            'bathrooms' => $property->bathrooms,
            'has_parking' => $property->has_parking,
            'has_elevator' => $property->has_elevator,
            'building_facade' => $property->building_facade,
            'address' => $property->address,
            'latitude' => $property->latitude,
            'longitude' => $property->longitude,
            'contact_phone' => $property->contact_phone,
            'contact_whatsapp' => $property->contact_whatsapp,
            'ownership_document_type' => $property->ownership_document_type,
            'document_owner_name' => $property->document_owner_name,
            'owner_relationship_type' => $property->owner_relationship_type,
            'owner_relationship_note' => $property->owner_relationship_note,
            'building_reference' => $property->building_reference,
            'unit_number' => $property->unit_number,
            'floor_number' => $property->floor_number,
            'land_boundary_geojson' => $property->land_boundary_geojson,
        ];
    }

    private function publicQuery(): Builder
    {
        return app(\App\Services\PropertyDiscoveryFilterService::class)->publicQuery()->with('images');
    }

    private function applyFilters(Builder $query, array $validated): void
    {
        app(\App\Services\PropertyDiscoveryFilterService::class)->apply($query, $validated);
    }

    private function validateBounds(array $validated): void
    {
        app(\App\Services\PropertyDiscoveryFilterService::class)->validateGeometry($validated);
    }

    private function applyBounds(Builder $query, array $validated): void
    {
        app(\App\Services\PropertyDiscoveryFilterService::class)->applyBounds($query, $validated);
    }

    private function assertOwner(Property $property, User $user): void
    {
        abort_unless((int) $property->user_id === (int) $user->id, 403);
    }

    private function syncLocation(Property $property): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement(
            'UPDATE properties SET location = ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography WHERE id = ?',
            [(float) $property->longitude, (float) $property->latitude, $property->id],
        );
    }

    private function storeImages(
        Request $request,
        Property $property,
        int $offset,
        array &$storedPaths,
    ): void
    {
        $files = $request->file('images', []);
        foreach ($files as $index => $file) {
            $path = $this->storage->storePublic($file, 'properties/' . $property->id);
            if (! is_string($path) || $path === '') {
                throw new \RuntimeException('The uploaded image could not be stored.');
            }
            $storedPaths[] = $path;
            $property->images()->create([
                'path' => $path,
                'cdn_url' => null,
                'sort_order' => $offset + $index,
                'is_primary' => ($offset + $index) === 0,
            ]);
        }
    }

    private function storeProofDocuments(Request $request, Property $property, User $user, array &$storedPaths): void
    {
        foreach ($request->file('proof_documents', []) as $file) {
            $path = $this->storage->storePrivate($file, 'listing_proofs/'.$property->id);
            if (! is_string($path) || $path === '') throw new \RuntimeException('Proof document could not be stored.');
            $storedPaths[] = $path;
            $property->documents()->create([
                'uploaded_by_user_id' => $user->id,
                'kind' => 'ownership_or_authorization',
                'path' => $path,
                'original_name' => $file->getClientOriginalName(),
                'mime_type' => $file->getMimeType(),
                'size_bytes' => $file->getSize(),
                'created_at' => now(),
            ]);
        }

        foreach ([
            'owner_id_front' => 'owner_id_front',
            'owner_id_back' => 'owner_id_back',
            'owner_selfie' => 'owner_selfie',
            'ownership_proof' => 'ownership_proof',
        ] as $field => $kind) {
            if (! $request->hasFile($field)) continue;
            $file = $request->file($field);
            if (! $file) continue;
            $path = $this->storage->storePrivate($file, 'listing_proofs/'.$property->id);
            if (! is_string($path) || $path === '') throw new \RuntimeException('Proof document could not be stored.');
            $storedPaths[] = $path;
            $old = $property->documents()->where('kind', $kind)->get();
            foreach ($old as $document) {
                $this->storage->deletePrivate($document->path);
                $document->delete();
            }
            $property->documents()->create([
                'uploaded_by_user_id' => $user->id,
                'kind' => $kind,
                'path' => $path,
                'original_name' => $file->getClientOriginalName(),
                'mime_type' => $file->getMimeType(),
                'size_bytes' => $file->getSize(),
                'created_at' => now(),
            ]);
        }
    }

    private function assertAdvertiserCanCreateDraft(User $user): void
    {
        $profile = $user->verificationProfile();
        if ($profile) {
            if (! $profile->isApproved()) {
                throw new ConflictHttpException('طلب نوع الحساب ما زال غير معتمد. أكمل التحقق قبل إنشاء إعلان جديد.');
            }
            return;
        }

        // Current WhatsApp UAT accounts must choose and verify a publishing
        // identity (owner/broker/office). A base researcher/browser/buyer account
        // can browse and buy, but cannot bypass verification by calling the API.
        if ((int) $user->identity_policy_version >= 1) {
            throw new ConflictHttpException('اختر نوع الحساب من حسابي وأكمل التحقق قبل إنشاء إعلان جديد.');
        }

        // Historical local/test compatibility only.
        if ($user->isBrokerAccount() && ! $user->isBrokerVerified()) {
            throw new ConflictHttpException('يجب توثيق حساب الدلال من فريق الدعم قبل رفع إعلان.');
        }
    }

    private function deleteProofFiles(iterable $documents): void { foreach($documents as $document){if($document->path)$this->storage->deletePrivate($document->path);} }
    private function deletePrivatePaths(array $paths): void { foreach($paths as $path)$this->storage->deletePrivate($path); }

    private function deleteImageFiles(iterable $images): void
    {
        foreach ($images as $image) {
            if (! $image->cdn_url && $image->path) {
                if (str_starts_with($image->path,'editor-drafts/')) $this->storage->deletePrivate($image->path); else $this->storage->deletePublic($image->path);
            }
        }
    }

    private function deletePaths(array $paths): void
    {
        foreach ($paths as $path) {
            $this->storage->deletePublic($path);
        }
    }

    private function summaryData(Property $property, Request $request): array
    {
        $property->loadMissing('images');
        $mainImage = $property->images->first();

        $data = [
            'id' => $property->id,
            'title' => $property->title,
            'purpose' => $property->purpose,
            'type' => $property->type,
            'unit_occupies_entire_floor' => $property->type === 'floor' || (bool) $property->unit_occupies_entire_floor,
            'tenure_type' => $property->tenure_type,
            'price' => (float) $property->price,
            'currency' => $property->currency,
            'area_m2' => $property->area_m2,
            'area_value' => $property->area_value !== null ? (float) $property->area_value : ($property->area_m2 !== null ? (float) $property->area_m2 : null),
            'area_unit' => $property->area_unit ?? ($property->area_m2 !== null ? 'sqm' : null),
            'bedrooms' => $property->bedrooms,
            'bathrooms' => $property->bathrooms,
            'has_parking' => $property->has_parking,
            'has_elevator' => $property->has_elevator,
            'building_facade' => $property->building_facade,
            'address' => $property->address,
            'latitude' => (float) $property->latitude,
            'longitude' => (float) $property->longitude,
            'status' => $property->status === 'published' && !$property->isPubliclyAvailable() ? 'unavailable' : $property->status,
            'availability_status' => $property->availability_status ?? 'available',
            'availability_confirmed_at' => $property->availability_confirmed_at?->toIso8601String(),
            'availability_due_at' => $property->availability_due_at?->toIso8601String(),
            'view_count' => (int) $property->view_count,
            'main_image' => $mainImage ? $this->imageUrl($mainImage, $request) : null,
            'image_urls' => $property->images->take(12)->map(fn ($image) => $this->imageUrl($image, $request))->values(),
            'image_count' => $property->images->count(),
            'floor_number' => in_array($property->type, ['apartment', 'floor', 'office', 'shop'], true) ? $property->floor_number : null,
            'is_spotlight' => $property->isPubliclyAvailable() && $property->spotlight_until?->isFuture() === true,
        ];
        return array_intersect_key(app(\App\Services\DynamicPropertySchema::class)->facts($data,true),$data);
    }

    private function mineWorkspaceData(Property $property, Request $request): array
    {
        $property->loadMissing(['images', 'documents']);
        return array_merge($this->summaryData($property, $request), [
            'description' => $property->description,
            'rental_conditions' => $property->rental_conditions ?? [],
            'contact_phone' => $property->contact_phone,
            'contact_whatsapp' => $property->contact_whatsapp,
            'review_status' => $property->review_status,
            'geo_cell_id' => $property->geo_cell_id,
            'property_asset_id' => $property->property_asset_id,
            'last_review_reason' => $property->last_review_reason,
            'proof_document_count' => $property->documents->count(),
            'can_submit' => in_array($property->review_status, ['draft', 'returned_for_correction'], true),
            'can_edit' => ! in_array($property->review_status, ['submitted', 'under_review', 'rejected_blocked'], true),
            'is_owner' => true,
            'status' => $property->status,
            'favorite_count' => (int) $property->favorite_count,
            'conversation_count' => (int) $property->conversation_count,
            'viewing_count' => (int) $property->viewing_count,
            'ownership_document_type' => $property->ownership_document_type,
            'document_owner_name' => $property->document_owner_name,
            'owner_relationship_type' => $property->owner_relationship_type,
            'owner_relationship_note' => $property->owner_relationship_note,
            'building_reference' => $property->building_reference,
            'unit_number' => $property->unit_number,
            'floor_number' => $property->floor_number,
            'land_boundary_geojson' => $property->land_boundary_geojson,
            'duplicate_check_status' => $property->duplicate_check_status,
            'duplicate_check_score' => (int) $property->duplicate_check_score,
            'duplicate_check_metadata' => $property->duplicate_check_metadata,
            'ownership_proof_present' => $property->documents->contains(
                fn (ListingDocument $document) => $document->kind === 'ownership_proof'
            ),
            'images' => $property->images
                ->map(fn (PropertyImage $image) => [
                    'id' => $image->id,
                    'url' => $this->imageUrl($image, $request),
                    'is_primary' => (bool) $image->is_primary,
                    'sort_order' => (int) $image->sort_order,
                ])
                ->values(),
        ]);
    }

    private function detailData(Property $property, Request $request): array
    {
        $property->loadMissing(['images','user.accountVerificationProfile.documents']);
        $ratingQuery=AdvertiserRating::query()->confirmedCustomerRatings()->where('advertiser_user_id',$property->user_id)->where('status','visible');
        $ratingCount=(clone $ratingQuery)->count();
        $ratingAverage=$ratingCount>0?round((float)(clone $ratingQuery)->avg('rating'),2):0.0;
        $commentCount=ListingComment::query()->where('property_id',$property->id)->where('status','visible')->count();

        $data = array_merge($this->summaryData($property, $request), [
            'description' => $property->description,
            'rental_conditions' => $property->rental_conditions ?? [],
            'advertiser' => array_merge([
                'id'=>(int)$property->user_id,
                'name'=>$this->advertiserDisplayName($property->user),
                'rating_average'=>$ratingAverage,
                'rating_count'=>$ratingCount,
            ], $this->advertiserVerificationData($property)),
            'community' => ['comments_count'=>$commentCount],
            'images' => $property->images
                ->map(fn (PropertyImage $image) => [
                    'id' => $image->id,
                    'url' => $this->imageUrl($image, $request),
                    'is_primary' => (bool) $image->is_primary,
                    'sort_order' => (int) $image->sort_order,
                ])
                ->values(),
        ]);

        $viewer = $this->tokens->authenticate($request, false);
        if ($viewer !== null && (int) $viewer->id === (int) $property->user_id) {
            $data['contact_phone'] = $property->contact_phone;
            $data['contact_whatsapp'] = $property->contact_whatsapp;
            $data['review_status'] = $property->review_status;
            $data['geo_cell_id'] = $property->geo_cell_id;
            $data['property_asset_id'] = $property->property_asset_id;
            $data['last_review_reason'] = $property->last_review_reason;
            $data['proof_document_count'] = $property->documents()->count();
            $data['can_submit'] = in_array($property->review_status, ['draft','returned_for_correction'], true);
            $data['can_edit'] = ! in_array($property->review_status, ['submitted','under_review','rejected_blocked'], true);
            $data['ownership_document_type'] = $property->ownership_document_type;
            $data['document_owner_name'] = $property->document_owner_name;
            $data['owner_relationship_type'] = $property->owner_relationship_type;
            $data['owner_relationship_note'] = $property->owner_relationship_note;
            $data['building_reference'] = $property->building_reference;
            $data['unit_number'] = $property->unit_number;
            $data['floor_number'] = $property->floor_number;
            $data['land_boundary_geojson'] = $property->land_boundary_geojson;
            $data['duplicate_check_status'] = $property->duplicate_check_status;
            $data['duplicate_check_score'] = (int) $property->duplicate_check_score;
            $data['duplicate_check_metadata'] = $property->duplicate_check_metadata;
            $data['ownership_proof_present'] = $property->documents()->where('kind', 'ownership_proof')->exists();
        }
        return array_intersect_key(app(\App\Services\DynamicPropertySchema::class)->facts($data,true),$data);
    }

    private function advertiserDisplayName(?User $user): string
    {
        if (! $user) return 'Advertiser';
        $profile = $user->accountVerificationProfile;
        if ($profile?->isApproved() && $profile->type === 'office') {
            $officeName = trim((string) (($profile->details ?? [])['office_name'] ?? ''));
            if ($officeName !== '') return $officeName;
        }
        return $user->name;
    }

    private function advertiserVerificationData(Property $property): array
    {
        $profile = $property->user?->accountVerificationProfile;
        if (! $profile || ! $profile->isApproved()) {
            return [
                'verification_type' => null,
                'verification_label' => 'معلن',
                'verification_status' => $profile?->status ?? 'not_submitted',
                'verification_flags' => [
                    'identity_reviewed' => false,
                    'relationship_document_reviewed' => false,
                    'professional_document_reviewed' => false,
                    'commercial_register_reviewed' => false,
                    'office_documents_reviewed' => false,
                    'office_location_registered' => false,
                ],
            ];
        }

        $kinds = $profile->documents->pluck('kind');
        $details = $profile->details ?? [];
        $professional = $profile->type === 'broker' && $kinds->contains('professional_license');
        $label = match ($profile->type) {
            'owner' => 'مالك العقار',
            'broker' => $professional ? 'دلال مهني' : 'دلال',
            'office' => 'مكتب عقاري',
            default => 'معلن',
        };
        return [
            'verification_type' => $profile->type,
            'verification_label' => $label,
            'verification_status' => $profile->status,
            'verification_flags' => [
                'identity_reviewed' => true,
                'relationship_document_reviewed' => $profile->type === 'owner'
                    && $property->status === 'published'
                    && $property->documents()->where('kind', 'ownership_proof')->exists(),
                'professional_document_reviewed' => $professional,
                'commercial_register_reviewed' => $profile->type === 'office' && $kinds->contains('commercial_register'),
                'office_documents_reviewed' => $profile->type === 'office' && $kinds->contains('office_license'),
                'office_location_registered' => $profile->type === 'office' && isset($details['latitude'], $details['longitude']),
            ],
        ];
    }

    private function imageUrl(PropertyImage $image, Request $request): string
    {
        $raw = trim((string) $image->cdn_url);
        if ($raw !== '') {
            if (str_starts_with($raw, 'http://') || str_starts_with($raw, 'https://')) {
                return $raw;
            }
            return rtrim($request->getSchemeAndHttpHost(), '/') . '/' . ltrim($raw, '/');
        }

        return rtrim($request->getSchemeAndHttpHost(), '/') . '/api/property-media/' . $image->id;
    }

    private function distanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadiusKm = 6371.0088;
        $latDelta = deg2rad($lat2 - $lat1);
        $lngDelta = deg2rad($lng2 - $lng1);

        $a = sin($latDelta / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($lngDelta / 2) ** 2;

        $a = max(0.0, min(1.0, $a));

        return $earthRadiusKm * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}
