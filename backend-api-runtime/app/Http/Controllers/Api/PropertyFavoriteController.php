<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyFavorite;
use App\Models\PropertyImage;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PropertyFavoriteController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $perPage = max(1, min((int) $request->input('per_page', 20), 50));

        $page = PropertyFavorite::query()
            ->where('user_id', $user->id)
            ->latest('id')
            ->paginate($perPage);

        // Load listing fields/media in one batch, restricted to public rows.
        // Unavailable favorites never fetch or serialize unpublished details.
        $publicProperties = Property::query()
            ->whereIn('id', collect($page->items())->pluck('property_id'))
            ->where('status', 'published')
            ->with('images')
            ->get()
            ->keyBy('id');

        return response()->json([
            'data' => collect($page->items())
                ->map(fn (PropertyFavorite $favorite): array => $this->favoriteData(
                    $favorite, $publicProperties->get($favorite->property_id), $request,
                ))
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function ids(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $ids = PropertyFavorite::query()
            ->where('user_id', $user->id)
            ->latest('id')
            ->pluck('property_id')
            ->map(fn ($id) => (int) $id)
            ->values();

        return response()->json(['data' => ['property_ids' => $ids]]);
    }

    public function store(Request $request, string $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $favorite = DB::transaction(function () use ($user, $property): PropertyFavorite {
            // Unknown and unpublished IDs have the same 404. Hold publication
            // stable until the favorite write completes, including on PostgreSQL.
            $published = Property::query()
                ->whereKey($property)
                ->where('status', 'published')
                ->sharedLock()
                ->first(['id']);
            abort_unless($published, 404);

            return PropertyFavorite::query()->firstOrCreate([
                'user_id' => $user->id,
                'property_id' => $published->id,
            ]);
        });

        return response()->json([
            'message' => 'Property saved to favorites.',
            'data' => [
                'property_id' => (int) $favorite->property_id,
                'is_favorited' => true,
                'favorited_at' => $favorite->created_at?->toIso8601String(),
                'availability' => 'available',
            ],
        ]);
    }

    public function destroy(Request $request, string $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        // Ownership of the favorite authorizes removal, independently of the
        // listing. No Property binding/lookup: absent and private IDs are alike.
        PropertyFavorite::query()
            ->where('user_id', $user->id)
            ->where('property_id', $property)
            ->delete();

        return response()->json([
            'message' => 'Property removed from favorites.',
            'data' => [
                'property_id' => (int) $property,
                'is_favorited' => false,
            ],
        ]);
    }

    public function status(Request $request, string $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $favorite = PropertyFavorite::query()
            ->with('property:id,status')
            ->where('user_id', $user->id)
            ->where('property_id', $property)
            ->first();

        // Only an owned favorite permits an unavailable-status response.
        // Without one, lookup sees public listings only, including for advertisers.
        $visible = $favorite?->property ?? Property::query()
            ->whereKey($property)
            ->where('status', 'published')
            ->first(['id', 'status']);
        abort_unless($visible, 404);

        return response()->json([
            'data' => [
                'property_id' => (int) $visible->id,
                'is_favorited' => $favorite !== null,
                'availability' => $visible->status === 'published' ? 'available' : 'unavailable',
            ],
        ]);
    }

    private function favoriteData(PropertyFavorite $favorite, ?Property $publicProperty, Request $request): array
    {
        $available = $publicProperty !== null;
        $data = [
            'property_id' => (int) $favorite->property_id,
            'is_favorited' => true,
            'favorited_at' => $favorite->created_at?->toIso8601String(),
            'availability' => $available ? 'available' : 'unavailable',
        ];

        if ($available) {
            $data['property'] = $this->summary($publicProperty, $request);
        } else {
            // No snapshot exists. Never serialize current unpublished fields,
            // including title, or load private/current images for this branch.
            $data['message'] = 'هذا العقار محفوظ في المفضلة لكنه غير متاح حالياً.';
        }

        return $data;
    }

    private function summary(Property $property, Request $request): array
    {
        $property->loadMissing('images');
        $mainImage = $property->images->first();

        return [
            'id' => (int) $property->id,
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
            'address' => $property->address,
            'latitude' => (float) $property->latitude,
            'longitude' => (float) $property->longitude,
            'status' => $property->status,
            'main_image' => $mainImage ? $this->imageUrl($mainImage, $request) : null,
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
}
