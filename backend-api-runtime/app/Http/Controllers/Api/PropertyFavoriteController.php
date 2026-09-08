<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyFavorite;
use App\Models\PropertyImage;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PropertyFavoriteController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $perPage = max(1, min((int) $request->input('per_page', 20), 50));

        $page = PropertyFavorite::query()
            ->with(['property.images'])
            ->where('user_id', $user->id)
            ->whereHas('property', fn ($query) => $query->where('status', 'published'))
            ->latest('id')
            ->paginate($perPage);

        return response()->json([
            'data' => collect($page->items())
                ->map(function (PropertyFavorite $favorite) use ($request): array {
                    return [
                        'favorited_at' => $favorite->created_at?->toIso8601String(),
                        'property' => $this->summary($favorite->property, $request),
                    ];
                })
                ->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function store(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($property->status === 'published', 404);

        $favorite = PropertyFavorite::query()->firstOrCreate([
            'user_id' => $user->id,
            'property_id' => $property->id,
        ]);

        return response()->json([
            'message' => 'Property saved to favorites.',
            'data' => [
                'property_id' => (int) $property->id,
                'is_favorited' => true,
                'favorited_at' => $favorite->created_at?->toIso8601String(),
            ],
        ]);
    }

    public function destroy(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        PropertyFavorite::query()
            ->where('user_id', $user->id)
            ->where('property_id', $property->id)
            ->delete();

        return response()->json([
            'message' => 'Property removed from favorites.',
            'data' => [
                'property_id' => (int) $property->id,
                'is_favorited' => false,
            ],
        ]);
    }

    public function status(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($property->status === 'published', 404);

        return response()->json([
            'data' => [
                'property_id' => (int) $property->id,
                'is_favorited' => PropertyFavorite::query()
                    ->where('user_id', $user->id)
                    ->where('property_id', $property->id)
                    ->exists(),
            ],
        ]);
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
