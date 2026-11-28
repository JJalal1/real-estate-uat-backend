<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportTask;
use App\Models\SupportTeam;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

class SupportTeamStatistics
{
    public function __construct(private readonly SupportTeamRoutingService $routing) {}

    public function forManager(User $actor, string $from, string $to): array
    {
        abort_unless($actor->hasRole('support_manager') || $actor->hasPermission('support.manage')
            || $actor->is_platform_owner || $actor->hasRole('super_admin'), 403);

        $teams = DB::table('support_teams')->whereIn('id', $this->routing->managedTeamIds($actor))
            ->where('is_active', true)->get(['id', 'governorate_id']);
        $teamIds = $teams->pluck('id')->all();
        $governorates = $teams->pluck('governorate_id')->filter()->unique()->values()->all();

        return $this->measure($teamIds, $governorates, $from, $to, includeResponseTime: true);
    }

    public function forExecutive(User $actor, string $from, string $to, ?int $governorate): array
    {
        abort_unless($actor->is_platform_owner || $actor->hasRole('super_admin'), 403);
        $teams = SupportTeam::query()->select('support_teams.*')->where('is_active', true)
            ->when($governorate, fn ($query) => $query->where('governorate_id', $governorate))
            ->with(['governorate:id,name_ar', 'manager:id,name,account_status'])
            ->selectSub(DB::table('support_team_members')->selectRaw('count(distinct user_id)')
                ->whereColumn('support_team_id', 'support_teams.id'), 'members_count')
            ->orderBy('is_fallback')->orderBy('name_ar')->get();

        [$start, $end] = $this->bounds($from, $to);
        $closed = implode(',', array_fill(0, count(SupportTaskService::CLOSED_STATUSES), '?'));
        $active = implode(',', array_fill(0, count(SupportTaskService::ACTIVE_STATUSES), '?'));
        $counts = SupportTask::query()->whereIn('support_team_id', $teams->modelKeys())
            ->whereNotIn('source_type', ['contact_followup', 'account_verification'])
            ->select('support_team_id')
            ->selectRaw('SUM(CASE WHEN created_at >= ? AND created_at < ? THEN 1 ELSE 0 END) AS received',
                [$start, $end])
            ->selectRaw("SUM(CASE WHEN status IN ($closed) AND completed_at >= ? AND completed_at < ? THEN 1 ELSE 0 END) AS completed",
                [...SupportTaskService::CLOSED_STATUSES, $start, $end])
            ->selectRaw("SUM(CASE WHEN status IN ($active) AND sla_due_at <= ? THEN 1 ELSE 0 END) AS overdue",
                [...SupportTaskService::ACTIVE_STATUSES, now()])
            ->groupBy('support_team_id')->get()->keyBy('support_team_id');
        $province = DB::raw('COALESCE(cell.governorate_id, review.governorate_id)');
        $published = DB::table('properties as property')
            ->leftJoin('geo_cells as cell', 'cell.id', '=', 'property.geo_cell_id')
            ->leftJoin('support_tasks as review', function ($join): void {
                $join->on('review.source_id', '=', 'property.id')->where('review.source_type', 'listing_review')
                    ->whereNull('property.geo_cell_id');
            })
            ->whereIn($province, $teams->pluck('governorate_id')->filter()->unique()->all())
            ->where('property.published_at', '>=', $start)->where('property.published_at', '<', $end)
            ->selectRaw('COALESCE(cell.governorate_id, review.governorate_id) AS governorate_id, COUNT(*) AS total')
            ->groupBy($province)->pluck('total', 'governorate_id');

        $rows = $teams->map(function (SupportTeam $team) use ($counts, $published): array {
            $work = $counts->get($team->id);
            return [
                'id' => $team->id,
                'name' => $team->name_ar,
                'governorate_id' => $team->governorate_id,
                'governorate_name' => $team->governorate?->name_ar,
                'is_fallback' => $team->is_fallback,
                'manager_id' => $team->manager?->isActive() ? $team->manager_user_id : null,
                'manager_name' => $team->manager?->isActive() ? $team->manager->name : null,
                'members' => $team->members_count,
                'received' => (int) ($work?->received ?? 0),
                'completed' => (int) ($work?->completed ?? 0),
                'overdue' => (int) ($work?->overdue ?? 0),
                'published' => (int) $published->get($team->governorate_id, 0),
            ];
        });

        return [
            'teams' => $rows->values()->all(),
            'totals' => [
                'received' => $rows->sum('received'),
                'completed' => $rows->sum('completed'),
                'overdue' => $rows->sum('overdue'),
                'published' => $published->sum(),
                'from' => $from,
                'to' => $to,
            ],
        ];
    }

    private function measure(array $teamIds, array $governorates, string $from, string $to,
        bool $includeResponseTime = false): array
    {
        [$start, $end] = $this->bounds($from, $to);
        $tasks = SupportTask::query()->whereIn('support_team_id', $teamIds)
            ->whereNotIn('source_type', ['contact_followup', 'account_verification']);
        $received = (clone $tasks)->where('created_at', '>=', $start)->where('created_at', '<', $end);
        $completed = (clone $tasks)->whereIn('status', SupportTaskService::CLOSED_STATUSES)
            ->where('completed_at', '>=', $start)->where('completed_at', '<', $end);
        $properties = $this->provinceProperties($governorates);
        $totalMinutes = 0;
        $responseCount = 0;
        if ($includeResponseTime) {
            $responses = SupportCase::query()->whereIn('id', (clone $tasks)
                ->whereIn('source_type', ['report', 'support_ticket'])->select('source_id'))
                ->where('first_response_at', '>=', $start)->where('first_response_at', '<', $end);
            foreach ($responses->select(['id', 'created_at', 'first_response_at'])->lazyById() as $case) {
                $totalMinutes += max(0, $case->created_at->diffInMinutes($case->first_response_at));
                $responseCount++;
            }
        }

        return [
            'from' => $from,
            'to' => $to,
            'received' => (clone $received)->count(),
            'completed' => $completed->count(),
            'overdue' => (clone $tasks)->whereIn('status', SupportTaskService::ACTIVE_STATUSES)
                ->where('sla_due_at', '<=', now())->count(),
            'published' => (clone $properties)->where('published_at', '>=', $start)
                ->where('published_at', '<', $end)->count(),
            'reports' => $received->where('source_type', 'report')->count(),
            'pending_listings' => $properties->whereIn('review_status', ['submitted', 'under_review'])->count(),
            'average_first_response_minutes' => $responseCount ? (int) round($totalMinutes / $responseCount) : null,
        ];
    }

    public function provinceProperties(array $governorates): \Illuminate\Database\Eloquent\Builder
    {
        return Property::query()->where(function ($query) use ($governorates): void {
            $query->whereIn('geo_cell_id', DB::table('geo_cells')->select('id')
                ->whereIn('governorate_id', $governorates))
                ->orWhere(fn ($legacy) => $legacy->whereNull('geo_cell_id')->whereIn('id',
                    SupportTask::query()->select('source_id')->where('source_type', 'listing_review')
                        ->whereIn('governorate_id', $governorates)));
        });
    }

    private function bounds(string $from, string $to): array
    {
        return [
            CarbonImmutable::parse($from, 'Asia/Aden')->startOfDay()->utc(),
            CarbonImmutable::parse($to, 'Asia/Aden')->addDay()->startOfDay()->utc(),
        ];
    }
}
