<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SavedPropertySearch;
use App\Models\User;
use App\Services\SavedPropertySearchService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SavedPropertySearchController extends Controller
{
    public function __construct(private readonly SavedPropertySearchService $searches) {}

    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $rows = SavedPropertySearch::query()
            ->where('user_id', $user->id)
            ->latest('updated_at')
            ->get();

        return response()->json([
            'data' => $rows->map(fn (SavedPropertySearch $row) => $this->data($row))->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $validated = $request->validate($this->rules(false));
        $filters = $this->searches->normalizeFilters((array) $validated['filters']);
        $fingerprint = $this->searches->fingerprint($filters);

        $existing = SavedPropertySearch::query()
            ->where('user_id', $user->id)
            ->where('fingerprint', $fingerprint)
            ->first();
        if ($existing) {
            return response()->json([
                'message' => 'هذا البحث محفوظ مسبقًا.',
                'data' => $this->data($existing),
            ], 200);
        }

        $row = SavedPropertySearch::query()->create([
            'user_id' => $user->id,
            'name' => trim((string) $validated['name']),
            'filters' => $filters,
            'fingerprint' => $fingerprint,
            'alert_frequency' => $validated['alert_frequency'] ?? 'instant',
            'is_active' => true,
            // Start from the current newest result so a new saved search does
            // not flood the user with historical matches.
            'last_match_property_id' => $this->searches->latestMatchId($filters),
            'last_checked_at' => now(),
        ]);

        return response()->json([
            'message' => 'تم حفظ البحث والتنبيه بنجاح.',
            'data' => $this->data($row),
        ], 201);
    }

    public function update(Request $request, SavedPropertySearch $savedSearch): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertOwner($savedSearch, $user);
        $validated = $request->validate($this->rules(true));

        if (array_key_exists('filters', $validated)) {
            $filters = $this->searches->normalizeFilters((array) $validated['filters']);
            $savedSearch->filters = $filters;
            $savedSearch->fingerprint = $this->searches->fingerprint($filters);
            $savedSearch->last_match_property_id = $this->searches->latestMatchId($filters);
            $savedSearch->last_checked_at = now();
        }
        if (array_key_exists('name', $validated)) {
            $savedSearch->name = trim((string) $validated['name']);
        }
        if (array_key_exists('alert_frequency', $validated)) {
            $savedSearch->alert_frequency = $validated['alert_frequency'];
        }
        if (array_key_exists('is_active', $validated)) {
            $savedSearch->is_active = (bool) $validated['is_active'];
        }
        $savedSearch->save();

        return response()->json([
            'message' => 'تم تحديث البحث المحفوظ.',
            'data' => $this->data($savedSearch->fresh()),
        ]);
    }

    public function destroy(Request $request, SavedPropertySearch $savedSearch): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertOwner($savedSearch, $user);
        $savedSearch->delete();
        return response()->json(['message' => 'تم حذف البحث المحفوظ.']);
    }

    private function rules(bool $partial): array
    {
        $required = $partial ? ['sometimes'] : ['required'];
        return [
            'name' => array_merge($required, ['string', 'max:120']),
            'alert_frequency' => ['sometimes', Rule::in(SavedPropertySearchService::ALERT_FREQUENCIES)],
            'is_active' => ['sometimes', 'boolean'],
            'filters' => array_merge($required, ['array']),
            'filters.search' => ['nullable', 'string', 'max:120'],
            'filters.purpose' => ['nullable', Rule::in(SavedPropertySearchService::PURPOSES)],
            'filters.type' => ['nullable', Rule::in(SavedPropertySearchService::TYPES)],
            'filters.min_price' => ['nullable', 'numeric', 'min:0'],
            'filters.max_price' => ['nullable', 'numeric', 'min:0'],
            'filters.min_bedrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'filters.min_bathrooms' => ['nullable', 'integer', 'min:0', 'max:50'],
            'filters.min_area_m2' => ['nullable', 'numeric', 'min:0'],
            'filters.max_area_m2' => ['nullable', 'numeric', 'min:0'],
            'filters.latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'filters.longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'filters.radius_km' => ['nullable', 'numeric', 'min:0.1', 'max:100'],
            'filters.south' => ['nullable', 'numeric', 'between:-90,90'],
            'filters.west' => ['nullable', 'numeric', 'between:-180,180'],
            'filters.north' => ['nullable', 'numeric', 'between:-90,90'],
            'filters.east' => ['nullable', 'numeric', 'between:-180,180'],
        ];
    }

    private function assertOwner(SavedPropertySearch $savedSearch, User $user): void
    {
        abort_unless((int) $savedSearch->user_id === (int) $user->id, 404);
    }

    private function data(SavedPropertySearch $row): array
    {
        return [
            'id' => (int) $row->id,
            'name' => $row->name,
            'filters' => $row->filters ?? [],
            'alert_frequency' => $row->alert_frequency,
            'is_active' => (bool) $row->is_active,
            'matching_count' => $this->searches->matchingCount($row->filters ?? []),
            'last_checked_at' => $row->last_checked_at?->toIso8601String(),
            'created_at' => $row->created_at?->toIso8601String(),
            'updated_at' => $row->updated_at?->toIso8601String(),
        ];
    }
}
