<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SavedPropertySearch;
use App\Models\User;
use App\Services\SavedPropertySearchService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

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
        $filters = $this->validatedFilters((array) $validated['filters']);
        $fingerprint = $this->searches->fingerprint($filters);

        [$row, $created] = DB::transaction(function () use ($user, $validated, $filters, $fingerprint): array {
            // Serialize this actor's writes across workers. The parent lock
            // also coordinates with account erasure and its child cleanup.
            $this->lockActiveActor($user);
            $existing = SavedPropertySearch::query()->where('user_id', $user->id)
                ->where('fingerprint', $fingerprint)->lockForUpdate()->first();
            if ($existing) return [$existing, false];

            return [SavedPropertySearch::query()->create([
                'user_id' => $user->id,
                'name' => trim((string) $validated['name']),
                'filters' => $filters,
                'fingerprint' => $fingerprint,
                'alert_frequency' => $validated['alert_frequency'] ?? 'instant',
                'is_active' => true,
                'last_match_property_id' => $this->searches->latestMatchId($filters),
                'last_checked_at' => now(),
            ]), true];
        }, 3);

        return response()->json([
            'message' => $created ? 'تم حفظ البحث والتنبيه بنجاح.' : 'هذا البحث محفوظ مسبقًا.',
            'data' => $this->data($row),
        ], $created ? 201 : 200);
    }

    public function update(Request $request, int $savedSearch): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $row = DB::transaction(function () use ($request, $savedSearch, $user): SavedPropertySearch {
            $this->lockActiveActor($user);
            $row = $this->ownedSearch($savedSearch, $user);
            $validated = $request->validate($this->rules(true));

            if (array_key_exists('filters', $validated)) {
                $filters = $this->validatedFilters((array) $validated['filters']);
                $fingerprint = $this->searches->fingerprint($filters);
                if (SavedPropertySearch::query()->where('user_id', $user->id)
                    ->where('fingerprint', $fingerprint)->where('id', '<>', $row->id)->exists()) {
                    throw ValidationException::withMessages(['filters' => 'هذه الشروط محفوظة في بحث آخر. افتح البحث الموجود لتعديله.']);
                }
                $row->filters = $filters;
                $row->fingerprint = $fingerprint;
                $row->last_match_property_id = $this->searches->latestMatchId($filters);
                $row->last_checked_at = now();
            }
            if (array_key_exists('name', $validated)) {
                $row->name = trim((string) $validated['name']);
            }
            if (array_key_exists('alert_frequency', $validated)) {
                $row->alert_frequency = $validated['alert_frequency'];
            }
            if (array_key_exists('is_active', $validated)) {
                $row->is_active = (bool) $validated['is_active'];
            }
            $row->save();
            return $row;
        }, 3);

        return response()->json([
            'message' => 'تم تحديث البحث المحفوظ.',
            'data' => $this->data($row),
        ]);
    }

    public function destroy(Request $request, int $savedSearch): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        DB::transaction(function () use ($savedSearch, $user): void {
            $this->lockActiveActor($user);
            $this->ownedSearch($savedSearch, $user)->delete();
        }, 3);
        return response()->json(['message' => 'تم حذف البحث المحفوظ.']);
    }

    private function ownedSearch(int $id, User $user): SavedPropertySearch
    {
        return SavedPropertySearch::query()
            ->whereKey($id)
            ->where('user_id', $user->id)
            ->lockForUpdate()
            ->firstOrFail();
    }

    private function lockActiveActor(User $actor): void
    {
        $current = User::query()->whereKey($actor->id)->lockForUpdate()->firstOrFail();
        abort_unless($current->isActive(), 403, 'هذا الحساب غير متاح للحفظ حاليًا.');
    }

    private function validatedFilters(array $input): array
    {
        $filters = $this->searches->normalizeFilters($input);
        if ($filters === []) {
            throw ValidationException::withMessages(['filters' => 'حدد شرطًا واحدًا على الأقل للبحث المحفوظ.']);
        }
        app(\App\Services\PropertyDiscoveryFilterService::class)->validateGeometry($filters);
        return $filters;
    }

    private function rules(bool $partial): array
    {
        $required = $partial ? ['sometimes'] : ['required'];
        $filterRules = app(\App\Services\PropertyDiscoveryFilterService::class)->rules();
        $rules = [
            'name' => array_merge($required, ['string', 'max:120']),
            'alert_frequency' => ['sometimes', Rule::in(SavedPropertySearchService::ALERT_FREQUENCIES)],
            'is_active' => ['sometimes', 'boolean'],
            'filters' => array_merge($required, ['array:'.implode(',', array_filter(array_keys($filterRules), fn ($key) => !str_contains($key, '.')))]),
        ];
        foreach ($filterRules as $key => $constraints) {
            $rules['filters.'.$key] = array_map(
                fn ($rule) => is_string($rule) && str_starts_with($rule, 'gte:')
                    ? 'gte:filters.'.substr($rule, 4) : $rule,
                $constraints,
            );
        }
        return $rules;
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
