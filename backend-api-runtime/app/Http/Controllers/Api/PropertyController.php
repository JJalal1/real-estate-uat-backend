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
    private const TYPES = ['apartment', 'house', 'villa', 'land', 'shop', 'office', 'farm'];
    private const PURPOSES = ['sale', 'rent'];
    private const TENURE_TYPES = ['freehold', 'waqf'];
    private const SALE_TENURE_PROPERTY_TYPES = ['apartment', 'house', 'villa', 'land', 'farm'];
    private const AREA_UNITS = [
        'sqm' => 1.0,
        'libna_sanaani' => 44.44,
        'libna_dhamari' => 114.49,
        'qasaba_taizi_ashari' => 20.25,
        'qasaba_taizi_hadawi' => 29.16,
        'qasaba_ibbi' => 56.25,
    ];
    private const FACADES = ['north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest', 'multiple'];
    private const RESIDENTIAL_TYPES = ['apartment', 'house', 'villa'];
    private const STRUCTURE_TYPES = ['apartment', 'house', 'villa', 'shop', 'office'];

    public function __construct(
        private readonly ApiTokenService $tokens,
        private readonly AuditLogService $audit,
        private readonly CloudAssetStorageService $storage,
        private readonly RegionService $regions,
        private readonly PropertyAssetService $assets,
        private readonly ListingWorkflowService $workflow,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $validated = $request->validate($this->filterRules());
        $perPage = max(1, min((int) ($request->input('per_page', 20)), 50));

        $query = $this->publicQuery();
        $this->applyFilters($query, $validated);

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

        $this->validateBounds($validated);

        $query = $this->publicQuery();
        $this->applyFilters($query, $validated);
        $this->applyBounds($query, $validated);

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

    public function show(Request $request, Property $property): JsonResponse
    {
        $user = $this->tokens->authenticate($request, false);
        $isOwner = $user !== null && (int) $property->user_id === (int) $user->id;
        abort_unless($property->status === 'published' || $isOwner, 404);

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

        $page = Property::query()
            ->with('images')
            ->where('user_id', $user->id)
            ->latest('id')
            ->paginate($perPage);

        return response()->json([
            'data' => collect($page->items())
                ->map(fn (Property $property) => $this->detailData($property, $request))
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        /** @var User $user */
        $user=$request->user();$this->assertAdvertiserCanCreateDraft($user);$validated=$request->validate($this->listingRules(false));
        $validated=$this->normalizeListingFields($validated,null,false);
        $this->assertV2ListingCompleteness($validated);
        $cell=$this->regions->assertListingAllowed($user,(float)$validated['latitude'],(float)$validated['longitude']);
        $asset=$this->assets->resolveOrCreate($user,$validated,null);
        $storedPublic=[];$storedPrivate=[];
        try{
            $property=DB::transaction(function()use($request,$validated,$user,$cell,$asset,&$storedPublic,&$storedPrivate){
                $property=Property::query()->create(array_merge($this->listingPayload($validated,false),['user_id'=>$user->id,'property_asset_id'=>$asset->id,'geo_cell_id'=>$cell?->id,'owner_key'=>null,'status'=>'draft','review_status'=>'draft']));
                $this->syncLocation($property);$this->storeImages($request,$property,0,$storedPublic);$this->storeProofDocuments($request,$property,$user,$storedPrivate);
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
            $wasPublished=$property->status==='published';$property->fill($this->listingPayload($validated,true));
            $cell=$this->regions->assertListingAllowed($user,(float)$property->latitude,(float)$property->longitude);$property->geo_cell_id=$cell?->id;
            $identity=array_merge(['purpose'=>$property->purpose,'type'=>$property->type,'latitude'=>$property->latitude,'longitude'=>$property->longitude,'area_m2'=>$property->area_m2,'bedrooms'=>$property->bedrooms,'bathrooms'=>$property->bathrooms,'address'=>$property->address],$validated);
            $asset=$this->assets->resolveOrCreate($user,$identity,null);$property->property_asset_id=$asset->id;
            $property->status='draft';$property->review_status='draft';$property->submitted_at=null;$property->reviewed_at=null;$property->last_review_reason=null;if($wasPublished)$property->published_at=null;$property->save();$this->syncLocation($property);
            if($replaceImages)$property->images()->delete();if($request->hasFile('images'))$this->storeImages($request,$property,$property->images()->count(),$storedPublic);$this->storeProofDocuments($request,$property,$user,$storedPrivate);
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
        DB::transaction(function()use($property,$user,$request):void{$property->delete();$this->audit->record($user,'listing.deleted',$property,['property_asset_id'=>$property->property_asset_id],$request,$user->id);});
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
        abort_unless($this->storage->existsPublic($image->path), 404);

        return $this->storage->responsePublic($image->path, null, [
            'Cache-Control' => 'public, max-age=86400',
        ]);
    }

    private function filterRules(): array
    {
        return [
            'search' => ['nullable', 'string', 'max:120'],
            'purpose' => ['nullable', Rule::in(self::PURPOSES)],
            'type' => ['nullable', Rule::in(self::TYPES)],
            'min_price' => ['nullable', 'numeric', 'min:0'],
            'max_price' => ['nullable', 'numeric', 'gte:min_price'],
            'min_bedrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'min_bathrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'min_area_m2' => ['nullable', 'numeric', 'min:0'],
            'max_area_m2' => ['nullable', 'numeric', 'gte:min_area_m2'],
        ];
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
            'listing_input_version' => ['nullable', 'integer', Rule::in([1, 2])],
            'area_m2' => ['nullable', 'integer', 'min:1', 'max:10000000'],
            'area_value' => ['nullable', 'numeric', 'gt:0', 'max:10000000'],
            'area_unit' => ['nullable', 'string', Rule::in(array_keys(self::AREA_UNITS))],
            'bedrooms' => ['nullable', 'integer', 'min:0', 'max:100'],
            'bathrooms' => ['nullable', 'integer', 'min:0', 'max:100'],
            'has_parking' => ['nullable', 'boolean'],
            'building_facade' => ['nullable', 'string', Rule::in(self::FACADES)],
            'address' => ['nullable', 'string', 'max:255'],
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
            'title', 'description', 'purpose', 'type', 'tenure_type', 'price', 'currency',
            'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'building_facade', 'address', 'latitude', 'longitude',
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
        }

        return $payload;
    }

    private function normalizeListingFields(array $validated, ?Property $existing, bool $partial): array
    {
        $hasAreaInput = array_key_exists('area_value', $validated) || array_key_exists('area_unit', $validated);
        $hasLegacyArea = array_key_exists('area_m2', $validated);

        if ($hasAreaInput) {
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
        } elseif ($hasLegacyArea) {
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
            $validated['building_facade'] = null;
        }

        return $validated;
    }

    private function assertV2ListingCompleteness(array $listing): void
    {
        if ((int) ($listing['listing_input_version'] ?? 1) !== 2) {
            return;
        }

        $errors = [];
        if (trim((string) ($listing['address'] ?? '')) === '') {
            $errors['address'][] = 'Address is required for listing input version 2.';
        }
        if (! isset($listing['area_value']) || (float) $listing['area_value'] <= 0 || empty($listing['area_unit'])) {
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
            'listing_input_version' => 1,
            'title' => $property->title,
            'description' => $property->description,
            'purpose' => $property->purpose,
            'type' => $property->type,
            'tenure_type' => $property->tenure_type,
            'price' => $property->price,
            'currency' => $property->currency,
            'area_m2' => $property->area_m2,
            'area_value' => $property->area_value ?? $property->area_m2,
            'area_unit' => $property->area_unit ?? 'sqm',
            'bedrooms' => $property->bedrooms,
            'bathrooms' => $property->bathrooms,
            'has_parking' => $property->has_parking,
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
        ];
    }

    private function publicQuery(): Builder
    {
        return Property::query()
            ->with('images')
            ->where('status', 'published');
    }

    private function applyFilters(Builder $query, array $validated): void
    {
        $search = trim((string) ($validated['search'] ?? ''));
        if ($search !== '') {
            $query->where(function (Builder $nested) use ($search) {
                $pattern = '%' . $search . '%';
                $operator = DB::connection()->getDriverName() === 'pgsql' ? 'ilike' : 'like';
                $nested
                    ->where('title', $operator, $pattern)
                    ->orWhere('description', $operator, $pattern)
                    ->orWhere('address', $operator, $pattern);
            });
        }

        foreach (['purpose', 'type'] as $field) {
            if (! empty($validated[$field])) {
                $query->where($field, $validated[$field]);
            }
        }

        $bounds = [
            'min_price' => ['price', '>='],
            'max_price' => ['price', '<='],
            'min_bedrooms' => ['bedrooms', '>='],
            'min_bathrooms' => ['bathrooms', '>='],
            'min_area_m2' => ['area_m2', '>='],
            'max_area_m2' => ['area_m2', '<='],
        ];

        foreach ($bounds as $input => [$column, $operator]) {
            if (isset($validated[$input])) {
                $query->where($column, $operator, $validated[$input]);
            }
        }
    }

    private function validateBounds(array $validated): void
    {
        $keys = ['south', 'west', 'north', 'east'];
        $provided = collect($keys)->filter(fn (string $key) => isset($validated[$key]));

        if ($provided->isNotEmpty() && $provided->count() !== count($keys)) {
            throw ValidationException::withMessages([
                'bounds' => ['All four map bounds are required together.'],
            ]);
        }

        if ($provided->count() === count($keys)
            && (float) $validated['south'] > (float) $validated['north']) {
            throw ValidationException::withMessages([
                'bounds' => ['The south bound must not exceed the north bound.'],
            ]);
        }
    }

    private function applyBounds(Builder $query, array $validated): void
    {
        if (! isset($validated['south'], $validated['west'], $validated['north'], $validated['east'])) {
            return;
        }

        $south = (float) $validated['south'];
        $west = (float) $validated['west'];
        $north = (float) $validated['north'];
        $east = (float) $validated['east'];

        $query->whereBetween('latitude', [$south, $north]);

        if ($west <= $east) {
            $query->whereBetween('longitude', [$west, $east]);
            return;
        }

        // A wrapped longitude range crosses the antimeridian.
        $query->where(function (Builder $nested) use ($west, $east) {
            $nested->where('longitude', '>=', $west)
                ->orWhere('longitude', '<=', $east);
        });
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
                $this->storage->deletePublic($image->path);
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

        return [
            'id' => $property->id,
            'title' => $property->title,
            'purpose' => $property->purpose,
            'type' => $property->type,
            'tenure_type' => $property->tenure_type,
            'price' => (float) $property->price,
            'currency' => $property->currency,
            'area_m2' => $property->area_m2,
            'area_value' => $property->area_value !== null ? (float) $property->area_value : ($property->area_m2 !== null ? (float) $property->area_m2 : null),
            'area_unit' => $property->area_unit ?? ($property->area_m2 !== null ? 'sqm' : null),
            'bedrooms' => $property->bedrooms,
            'bathrooms' => $property->bathrooms,
            'has_parking' => $property->has_parking,
            'building_facade' => $property->building_facade,
            'address' => $property->address,
            'latitude' => (float) $property->latitude,
            'longitude' => (float) $property->longitude,
            'status' => $property->status,
            'geo_cell_id' => $property->geo_cell_id,
            'property_asset_id' => $property->property_asset_id,
            'review_status' => $property->review_status,
            'main_image' => $mainImage ? $this->imageUrl($mainImage, $request) : null,
        ];
    }

    private function detailData(Property $property, Request $request): array
    {
        $property->loadMissing(['images','user.accountVerificationProfile.documents']);
        $ratingQuery=AdvertiserRating::query()->where('advertiser_user_id',$property->user_id)->where('status','visible');
        $ratingCount=(clone $ratingQuery)->count();
        $ratingAverage=$ratingCount>0?round((float)(clone $ratingQuery)->avg('rating'),2):0.0;
        $commentCount=ListingComment::query()->where('property_id',$property->id)->where('status','visible')->count();

        $data = array_merge($this->summaryData($property, $request), [
            'description' => $property->description,
            'contact_phone' => $property->contact_phone,
            'contact_whatsapp' => $property->contact_whatsapp,
            'last_review_reason' => $property->last_review_reason,
            'proof_document_count' => $property->documents()->count(),
            'can_submit' => in_array($property->review_status, ['draft','returned_for_correction'], true),
            'can_edit' => ! in_array($property->review_status, ['submitted','under_review','rejected_blocked'], true),
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
            $data['ownership_document_type'] = $property->ownership_document_type;
            $data['document_owner_name'] = $property->document_owner_name;
            $data['owner_relationship_type'] = $property->owner_relationship_type;
            $data['owner_relationship_note'] = $property->owner_relationship_note;
            $data['ownership_proof_present'] = $property->documents()->where('kind', 'ownership_proof')->exists();
        }
        return $data;
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
