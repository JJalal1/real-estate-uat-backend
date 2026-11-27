<?php

namespace App\Services;

use App\Models\Governorate;
use App\Models\Permission;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\SupportTeam;
use App\Models\SupportTeamMember;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class SupportTeamAdministrationService
{
    private const REVIEW_PERMISSIONS = [
        'review_payments' => 'payments.review',
        'review_listings' => 'listings.moderate',
    ];

    private const DELEGATION_REASON = 'تفويض مراجعة مهام فريق الدعم';

    public function __construct(private readonly AuditLogService $audit) {}

    public function candidates(string $term): array
    {
        $term = trim($term);
        if ($term === '') return [];

        $escaped = strtr(mb_strtolower($term), ['!' => '!!', '%' => '!%', '_' => '!_']);
        $like = '%'.$escaped.'%';

        return User::query()->where('account_status', User::STATUS_ACTIVE)
            ->whereNotNull('phone_verified_at')->where('is_platform_owner', false)
            ->whereDoesntHave('roles', fn ($roles) => $roles->where('key', 'super_admin'))
            ->where(function ($query) use ($like): void {
                $query->whereRaw("LOWER(name) LIKE ? ESCAPE '!'", [$like])
                    ->orWhereRaw("LOWER(email) LIKE ? ESCAPE '!'", [$like])
                    ->orWhereRaw("phone LIKE ? ESCAPE '!'", [$like]);
            })
            ->orderBy('name')->orderBy('id')->limit(25)
            ->get(['id', 'name', 'phone', 'email'])->toArray();
    }

    public function saveTeam(User $actor, int $governorateId, string $name, Request $request): SupportTeam
    {
        return DB::transaction(function () use ($actor, $governorateId, $name, $request): SupportTeam {
            $governorate = Governorate::query()->where('is_active', true)->lockForUpdate()->findOrFail($governorateId);
            $team = SupportTeam::query()->where('governorate_id', $governorate->id)
                ->where('is_fallback', false)->orderByDesc('is_active')->orderBy('id')
                ->lockForUpdate()->first();
            $team ??= new SupportTeam([
                'code' => 'gov-'.$governorate->code,
                'governorate_id' => $governorate->id,
                'is_fallback' => false,
            ]);
            $team->fill(['name_ar' => trim($name), 'is_active' => true])->save();
            $this->audit->record($actor, 'support_team.saved', $team, ['governorate_id' => $governorate->id], $request);

            return $team->load(['governorate', 'manager']);
        }, 3);
    }

    public function members(SupportTeam $team): array
    {
        $members = $team->members()->with('user')->get()->keyBy('user_id');
        $users = $members->pluck('user')->filter()->keyBy('id');
        if ($team->manager && !$users->has($team->manager_user_id)) $users->put($team->manager_user_id, $team->manager);

        return $users->sortBy('name')->map(fn (User $user) => $this->memberData(
            $team, $user, $members->get($user->id)
        ))->values()->all();
    }

    public function setMember(User $actor, SupportTeam $team, User $user, array $data, Request $request): array
    {
        return DB::transaction(function () use ($actor, $team, $user, $data, $request): array {
            $team = SupportTeam::query()->where('is_active', true)->lockForUpdate()->findOrFail($team->id);
            $user = User::query()->lockForUpdate()->findOrFail($user->id);
            abort_if($user->is_platform_owner || $user->hasRole('super_admin'), 403);
            abort_unless((!$data['agent'] && !$data['manager']) || $user->isActive(), 422, 'يمكن تفويض حساب نشط ومؤكد فقط.');

            $existing = $team->members()->where('user_id', $user->id)->lockForUpdate()->first();
            $oldManagerId = $team->manager_user_id;
            $preservePermissions = [];
            foreach (self::REVIEW_PERMISSIONS as $field => $key) {
                $preservePermissions[$field] = $user->hasPermission($key);
            }

            if ($data['agent']) {
                $otherAgentTeams = SupportTeamMember::query()->where('user_id', $user->id)
                    ->where('member_role', 'agent')->where('support_team_id', '<>', $team->id)
                    ->lockForUpdate()->pluck('support_team_id')->all();
                $otherManagerTeams = SupportTeam::query()->whereIn('id', $otherAgentTeams)
                    ->where('manager_user_id', $user->id)->pluck('id')->all();
                $this->assertNoOpenWork($user->id, $otherAgentTeams);
                SupportTeamMember::query()->where('user_id', $user->id)->whereIn('support_team_id', $otherManagerTeams)
                    ->update(['member_role' => 'manager']);
                SupportTeamMember::query()->where('user_id', $user->id)
                    ->whereIn('support_team_id', array_diff($otherAgentTeams, $otherManagerTeams))->delete();
            }

            if (!$data['agent'] && !$data['manager']) {
                $this->assertNoOpenWork($user->id, [$team->id]);
                $existing?->delete();
            } else {
                if (!$data['agent'] && $existing?->member_role === 'agent') {
                    $this->assertNoOpenWork($user->id, [$team->id]);
                }
                $existing ??= $team->members()->make(['user_id' => $user->id, 'joined_at' => now()]);
                $existing->fill([
                    'member_role' => $data['agent'] ? 'agent' : 'manager',
                    'is_available' => $data['is_available'] ?? $existing->is_available ?? true,
                    'capacity' => $data['capacity'] ?? $existing->capacity ?? 10,
                ])->save();
            }

            if ($data['manager']) {
                $team->manager_user_id = $user->id;
            } elseif ((int) $oldManagerId === (int) $user->id) {
                $team->manager_user_id = null;
            }
            if ($team->isDirty('manager_user_id')) {
                $team->save();
                if ($oldManagerId && (int) $oldManagerId !== (int) $user->id) {
                    $previous = User::query()->lockForUpdate()->find($oldManagerId);
                    $previousMembership = $team->members()->where('user_id', $oldManagerId)->first();
                    if ($previous && $previousMembership?->member_role !== 'agent') {
                        $this->assertNoOpenWork($previous->id, [$team->id]);
                        $previousMembership?->delete();
                    }
                    if ($previous) $this->syncRoles($actor, $previous);
                }
            }

            $user = $this->syncRoles($actor, $user);
            if ($user->hasRole('support_agent') || $user->hasRole('support_manager')) {
                foreach (self::REVIEW_PERMISSIONS as $field => $key) {
                    if (!array_key_exists($field, $data) && $user->hasPermission($key) === $preservePermissions[$field]) continue;
                    $allow = $data[$field] ?? $preservePermissions[$field];
                    if (!$allow && $preservePermissions[$field]) {
                        $source = $field === 'review_payments' ? 'payment_review' : 'listing_review';
                        if (SupportTask::query()->where('assigned_to_user_id', $user->id)
                            ->where('source_type', $source)->whereIn('status', SupportTaskService::ACTIVE_STATUSES)->exists()) {
                            throw new ConflictHttpException('أعد توزيع المهام المفتوحة قبل إلغاء صلاحية مراجعتها.');
                        }
                    }
                    $permission = Permission::query()->where('key', $key)->firstOrFail();
                    $user->permissionOverrides()->updateOrCreate(['permission_id' => $permission->id], [
                        'effect' => $allow ? 'allow' : 'deny',
                        'reason' => self::DELEGATION_REASON,
                        'assigned_by_user_id' => $actor->id,
                    ]);
                }
            }
            $user = $user->fresh();
            $result = $this->memberData($team, $user, $team->members()->where('user_id', $user->id)->first());
            $this->audit->record($actor, 'support_team.delegation_updated', $team, [
                ...$result, 'previous_manager_id' => $oldManagerId,
            ], $request, $user->id);

            return $result;
        }, 3);
    }

    private function assertNoOpenWork(int $userId, array $teamIds): void
    {
        if (SupportTask::query()->where('assigned_to_user_id', $userId)->whereIn('support_team_id', $teamIds)
            ->whereIn('status', SupportTaskService::ACTIVE_STATUSES)->exists()) {
            throw new ConflictHttpException('أعد توزيع المهام المفتوحة قبل تغيير فريق الموظف.');
        }
    }

    private function syncRoles(User $actor, User $user): User
    {
        $members = SupportTeamMember::query()->where('user_id', $user->id)
            ->whereHas('team', fn ($team) => $team->where('is_active', true));
        $roles = [
            'support_agent' => (clone $members)->where('member_role', 'agent')->exists(),
            'support_manager' => (clone $members)->where('member_role', 'manager')->exists()
                || SupportTeam::query()->where('is_active', true)->where('manager_user_id', $user->id)->exists(),
        ];
        foreach (Role::query()->whereIn('key', array_keys($roles))->get() as $role) {
            if ($roles[$role->key]) {
                if (!$user->hasRole($role->key)) {
                    $user->roles()->attach($role->id, ['assigned_by_user_id' => $actor->id, 'created_at' => now()]);
                }
            } else {
                $user->roles()->detach($role->id);
            }
        }
        if (!$roles['support_agent'] && !$roles['support_manager']) {
            $user->permissionOverrides()->where('reason', self::DELEGATION_REASON)->delete();
        }

        return $user->fresh();
    }

    private function memberData(SupportTeam $team, User $user, ?SupportTeamMember $member): array
    {
        return [
            'team_id' => (int) $team->id,
            'user_id' => (int) $user->id,
            'name' => $user->name,
            'agent' => $member?->member_role === 'agent',
            'manager' => (int) $team->manager_user_id === (int) $user->id || $member?->member_role === 'manager',
            'review_payments' => $user->hasPermission('payments.review'),
            'review_listings' => $user->hasPermission('listings.moderate'),
            'is_available' => $member?->is_available ?? true,
            'capacity' => $member?->capacity ?? 10,
        ];
    }
}
