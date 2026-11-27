<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\SerializesPropertyCards;
use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyFavorite;
use Illuminate\Support\Arr;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PropertyFavoriteController extends Controller
{
    use SerializesPropertyCards;

    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $perPage = max(1, min((int) $request->input('per_page', 20), 50));

        $page = PropertyFavorite::query()
            ->with(['property.images', 'property.currentSaiTerm'])
            ->where('user_id', $user->id)
            ->whereHas('property', fn ($query) => $query->publiclyVisible())
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

    public function ids(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $ids = PropertyFavorite::query()
            ->where('user_id', $user->id)
            ->whereHas('property', fn ($query) => $query->publiclyVisible())
            ->latest('id')
            ->limit(5000)
            ->pluck('property_id')
            ->map(fn ($id) => (int) $id)
            ->values();

        return response()->json([
            'data' => [
                'property_ids' => $ids,
            ],
        ]);
    }

    public function store(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertPubliclyAvailable($property);

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
        $this->assertPubliclyAvailable($property);

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

    private function assertPubliclyAvailable(Property $property): void
    {
        abort_unless($property->isPubliclyVisible(), 404);
    }

    private function summary(Property $property, Request $request): array
    {
        return array_merge(
            $this->summaryData($property, $request),
            Arr::only($this->publicPriceData($property, $property->currentSaiTerm), [
                'base_price', 'display_price', 'price_display_mode', 'price_display_note',
                'monthly_rent', 'rental_term_months', 'advance_months',
            ]),
        );
    }
}
