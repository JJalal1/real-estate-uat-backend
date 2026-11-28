<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Governorate;
use App\Models\SupportTeam;
use App\Models\User;
use App\Services\SupportTeamAdministrationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SupportTeamController extends Controller
{
    public function __construct(private readonly SupportTeamAdministrationService $teams) {}

    public function candidates(Request $request): JsonResponse
    {
        $this->authorizeAdministration($request);
        $data = $request->validate(['q' => ['nullable', 'string', 'max:120']]);

        return response()->json(['data' => $this->teams->candidates($data['q'] ?? '')]);
    }

    public function governorates(Request $request): JsonResponse
    {
        $this->authorizeAdministration($request);
        return response()->json(['data' => Governorate::query()->where('is_active', true)->orderBy('name_ar')
            ->get(['id', 'name_ar', 'code', 'is_active'])]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorizeAdministration($request);
        $data = $request->validate([
            'governorate_id' => ['required', 'integer', 'exists:governorates,id'],
            'name' => ['required', 'string', 'min:2', 'max:160'],
        ]);
        $team = $this->teams->saveTeam($request->user(), (int) $data['governorate_id'], $data['name'], $request);

        return response()->json(['data' => [
            'id' => (int) $team->id,
            'code' => $team->code,
            'name' => $team->name_ar,
            'governorate_id' => (int) $team->governorate_id,
            'governorate_name' => $team->governorate?->name_ar,
            'manager_user_id' => $team->manager_user_id,
            'manager_name' => $team->manager?->name,
            'is_fallback' => false,
        ]], $team->wasRecentlyCreated ? 201 : 200);
    }

    public function members(Request $request, SupportTeam $team): JsonResponse
    {
        $this->authorizeAdministration($request);
        abort_unless($team->is_active, 404);

        return response()->json(['data' => $this->teams->members($team)]);
    }

    public function setMember(Request $request, SupportTeam $team, User $user): JsonResponse
    {
        $this->authorizeAdministration($request);
        $validated = $request->validate([
            'agent' => ['required', 'boolean'],
            'manager' => ['required', 'boolean'],
            'review_payments' => ['sometimes', 'boolean'],
            'review_listings' => ['sometimes', 'boolean'],
            'is_available' => ['sometimes', 'boolean'],
            'capacity' => ['sometimes', 'integer', 'min:1', 'max:50'],
        ]);
        $data = ['agent' => $request->boolean('agent'), 'manager' => $request->boolean('manager')];
        foreach (['review_payments', 'review_listings', 'is_available'] as $field) {
            if (array_key_exists($field, $validated)) $data[$field] = $request->boolean($field);
        }
        if (array_key_exists('capacity', $validated)) $data['capacity'] = $request->integer('capacity');

        return response()->json(['data' => $this->teams->setMember($request->user(), $team, $user, $data, $request)]);
    }

    private function authorizeAdministration(Request $request): void
    {
        $actor = $request->user();
        abort_if($actor->hasRole('support_manager') && !$actor->is_platform_owner && !$actor->hasRole('super_admin'), 403);
    }
}
