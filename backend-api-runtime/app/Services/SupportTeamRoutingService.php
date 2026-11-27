<?php

namespace App\Services;

use App\Models\Governorate;
use App\Models\Property;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SupportTeamRoutingService
{
    public function fallbackTeamId(): ?int
    {
        if (!Schema::hasTable('support_teams')) return null;

        $id = DB::table('support_teams')->where('is_active', true)
            ->where('is_fallback', true)->orderBy('id')->value('id');

        return $id === null ? null : (int) $id;
    }

    public function teamId(?int $governorateId): ?int
    {
        if (!Schema::hasTable('support_teams')) return null;

        $id = $governorateId === null ? null : DB::table('support_teams')
            ->where('governorate_id', $governorateId)
            ->where('is_active', true)->where('is_fallback', false)
            ->orderBy('id')->value('id');

        return $id === null ? $this->fallbackTeamId() : (int) $id;
    }

    public function route(SupportTask $task, ?int $governorateId): SupportTask
    {
        if (!Schema::hasColumn('support_tasks', 'support_team_id')) return $task;
        if ($task->support_team_id && ($task->assigned_to_user_id || !$task->isActive())) return $task;

        $teamId = $this->teamId($governorateId);
        if ($teamId !== null) {
            $task->forceFill(['support_team_id' => $teamId, 'governorate_id' => $governorateId]);
            if ($task->isDirty(['support_team_id', 'governorate_id'])) {
                // A source refresh can race with the first claim.
                $updated = SupportTask::query()->whereKey($task->id)
                    ->whereNull('assigned_to_user_id')->whereIn('status', SupportTaskService::ACTIVE_STATUSES)
                    ->update(['support_team_id' => $teamId, 'governorate_id' => $governorateId]);
                if (!$updated && !$task->getOriginal('support_team_id')) {
                    SupportTask::query()->whereKey($task->id)->whereNull('support_team_id')
                        ->update(['support_team_id' => $teamId, 'governorate_id' => $governorateId]);
                }

                return $task->fresh(['team', 'governorate']);
            }
        }

        return $task;
    }

    public function refreshQueuedRouting(): void
    {
        if (request()->attributes->get(self::class) || !Schema::hasColumn('support_tasks', 'support_team_id')) return;

        $regionalTeam = DB::table('support_teams as team')->select('team.id')
            ->whereColumn('team.governorate_id', 'support_tasks.governorate_id')
            ->whereRaw('team.is_active AND NOT team.is_fallback')
            ->orderBy('team.id')->limit(1);
        DB::table('support_tasks')->whereNull('assigned_to_user_id')->whereNotNull('governorate_id')
            ->whereIn('status', SupportTaskService::INBOX_STATUSES)
            ->where(function ($queue) use ($regionalTeam): void {
                $queue->whereNull('support_team_id')->orWhere('support_team_id', '<>', $regionalTeam);
            })
            ->whereExists($regionalTeam)
            ->update(['support_team_id' => DB::raw('('.$regionalTeam->toSql().')')]);

        request()->attributes->set(self::class, true);
    }

    public function memberTeamIds(User $user, bool $agentsOnly = false): array
    {
        if (!Schema::hasTable('support_team_members')) return [];

        return DB::table('support_team_members as member')
            ->join('support_teams as team', 'team.id', '=', 'member.support_team_id')
            ->where('member.user_id', $user->id)->where('team.is_active', true)
            ->when($agentsOnly, fn ($query) => $query->where('member.member_role', 'agent'))
            ->pluck('team.id')->map(fn ($id) => (int) $id)->all();
    }

    public function managedTeamIds(User $actor): array
    {
        if (!Schema::hasTable('support_teams')) return [];

        $teams = DB::table('support_teams as team')->where('team.is_active', true);
        if (!$actor->is_platform_owner && !$actor->hasRole('super_admin')) {
            $teams->where(function ($query) use ($actor): void {
                $query->where('team.manager_user_id', $actor->id)
                    ->orWhereExists(function ($member) use ($actor): void {
                        $member->selectRaw('1')->from('support_team_members as member')
                            ->whereColumn('member.support_team_id', 'team.id')->where('member.user_id', $actor->id)
                            ->where('member.member_role', 'manager');
                    });
            });
        }

        return $teams->pluck('team.id')->map(fn ($id) => (int) $id)->all();
    }

    public function listingGovernorateId(?Property $property): ?int
    {
        if ($property?->geo_cell_id && Schema::hasTable('geo_cells')) {
            $id = DB::table('geo_cells')->where('id', $property->geo_cell_id)->value('governorate_id');
            if ($id) return (int) $id;
        }

        return $this->governorateIdFromName($property?->address);
    }

    public function governorateIdFromName(mixed $name): ?int
    {
        if (!is_string($name) || !Schema::hasTable('governorates')) return null;

        $needle = $this->normalize($name);
        if ($needle === '') return null;

        // Structured listing addresses put the selected governorate first.
        // Later parts can include another governorate's name as a street or district.
        if (preg_match('/^محافظه\s*:\s*(?:محافظه\s+)?([^،,\-]+)/u', $needle, $matches)) {
            $needle = trim($matches[1]);
        }

        $candidates = [];
        foreach (Governorate::query()->where('is_active', true)->get(['id', 'name_ar', 'name_en']) as $governorate) {
            foreach ([$governorate->name_ar, $governorate->name_en] as $alias) {
                $alias = $this->normalize((string) $alias);
                if ($needle === $alias) return (int) $governorate->id;
                if ($alias !== '' && preg_match('/(?<![\p{L}\p{N}])'.preg_quote($alias, '/').'(?![\p{L}\p{N}])/u', $needle)) {
                    $candidates[(int) $governorate->id] = true;
                }
            }
        }

        return count($candidates) === 1 ? array_key_first($candidates) : null;
    }

    private function normalize(string $text): string
    {
        $text = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', mb_strtolower($text)) ?? $text;

        return trim(strtr($text, ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ى' => 'ي', 'ؤ' => 'و', 'ئ' => 'ي', 'ة' => 'ه']));
    }
}
