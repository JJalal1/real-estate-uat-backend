<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportTask;
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
        $start = CarbonImmutable::parse($from, 'Asia/Aden')->startOfDay()->utc();
        $end = CarbonImmutable::parse($to, 'Asia/Aden')->addDay()->startOfDay()->utc();
        $tasks = SupportTask::query()->whereIn('support_team_id', $teamIds)
            ->whereNotIn('source_type', ['contact_followup', 'account_verification']);
        $received = (clone $tasks)->where('created_at', '>=', $start)->where('created_at', '<', $end);
        $completed = (clone $tasks)->whereIn('status', SupportTaskService::CLOSED_STATUSES)
            ->where('completed_at', '>=', $start)->where('completed_at', '<', $end);
        $properties = Property::query()->where(function ($query) use ($governorates): void {
            $query->whereIn('geo_cell_id', DB::table('geo_cells')->select('id')
                ->whereIn('governorate_id', $governorates))
                ->orWhere(fn ($legacy) => $legacy->whereNull('geo_cell_id')->whereIn('id',
                    SupportTask::query()->select('source_id')->where('source_type', 'listing_review')
                        ->whereIn('governorate_id', $governorates)));
        });
        $responses = SupportCase::query()->whereIn('id', (clone $tasks)
            ->whereIn('source_type', ['report', 'support_ticket'])->select('source_id'))
            ->where('first_response_at', '>=', $start)->where('first_response_at', '<', $end);
        $totalMinutes = 0;
        $responseCount = 0;
        foreach ($responses->select(['id', 'created_at', 'first_response_at'])->lazyById() as $case) {
            $totalMinutes += max(0, $case->created_at->diffInMinutes($case->first_response_at));
            $responseCount++;
        }

        return [
            'from' => $from,
            'to' => $to,
            'received' => (clone $received)->count(),
            'completed' => $completed->count(),
            'published' => (clone $properties)->where('published_at', '>=', $start)
                ->where('published_at', '<', $end)->count(),
            'reports' => $received->where('source_type', 'report')->count(),
            'pending_listings' => $properties->whereIn('review_status', ['submitted', 'under_review'])->count(),
            'average_first_response_minutes' => $responseCount ? (int) round($totalMinutes / $responseCount) : null,
        ];
    }
}
