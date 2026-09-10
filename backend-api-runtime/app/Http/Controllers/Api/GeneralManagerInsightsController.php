<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\SupportTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class GeneralManagerInsightsController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        if (! $actor || ! ($actor->is_platform_owner || $actor->hasRole('super_admin'))) {
            abort(403);
        }

        $today = now()->startOfDay();
        $activeTasks = SupportTask::query()->whereIn('status', SupportTaskService::ACTIVE_STATUSES);
        $published = Property::query()->where('status', 'published');

        $propertyTypes = (clone $published)
            ->selectRaw('type, COUNT(*) AS total')
            ->groupBy('type')
            ->orderByDesc('total')
            ->get()
            ->map(fn ($row) => [
                'type' => (string) $row->type,
                'total' => (int) $row->total,
            ])->values()->all();

        $governorates = [];
        if (Schema::hasTable('geo_cells') && Schema::hasTable('governorates') && Schema::hasColumn('properties', 'geo_cell_id')) {
            $governorates = DB::table('properties as p')
                ->join('geo_cells as c', 'c.id', '=', 'p.geo_cell_id')
                ->join('governorates as g', 'g.id', '=', 'c.governorate_id')
                ->where('p.status', 'published')
                ->selectRaw("g.id, g.name_ar, COUNT(*) AS total, SUM(CASE WHEN p.purpose = 'sale' THEN 1 ELSE 0 END) AS sale, SUM(CASE WHEN p.purpose = 'rent' THEN 1 ELSE 0 END) AS rent")
                ->groupBy('g.id', 'g.name_ar')
                ->orderByDesc('total')
                ->limit(30)
                ->get()
                ->map(fn ($row) => [
                    'id' => (int) $row->id,
                    'name' => (string) $row->name_ar,
                    'total' => (int) $row->total,
                    'sale' => (int) $row->sale,
                    'rent' => (int) $row->rent,
                ])->values()->all();
        }

        $approvedBrokers = 0;
        $approvedOffices = 0;
        $pendingProfessionals = 0;
        if (Schema::hasTable('account_verification_profiles')) {
            $approvedBrokers = DB::table('account_verification_profiles')
                ->where('type', 'broker')->where('status', 'approved')->count();
            $approvedOffices = DB::table('account_verification_profiles')
                ->where('type', 'office')->where('status', 'approved')->count();
            $pendingProfessionals = DB::table('account_verification_profiles')
                ->whereIn('type', ['broker', 'office'])
                ->whereIn('status', ['pending', 'needs_more_info'])
                ->count();
        }

        $journey = [
            'conversations' => Schema::hasTable('conversations') ? DB::table('conversations')->count() : null,
            'viewings' => Schema::hasTable('viewing_bookings') ? DB::table('viewing_bookings')->count() : null,
            'agreements' => Schema::hasTable('agreements') ? DB::table('agreements')->count() : null,
            'rental_contracts' => Schema::hasTable('rental_contracts') ? DB::table('rental_contracts')->count() : null,
        ];

        $team = [
            'support_agents' => User::query()
                ->whereHas('roles', fn ($q) => $q->where('roles.key', 'support_agent'))
                ->where('account_status', User::STATUS_ACTIVE)->count(),
            'support_managers' => User::query()
                ->whereHas('roles', fn ($q) => $q->where('roles.key', 'support_manager'))
                ->where('account_status', User::STATUS_ACTIVE)->count(),
        ];

        return response()->json(['data' => [
            'mode' => 'general_manager',
            'overview' => [
                'users_total' => User::query()->count(),
                'users_new_today' => User::query()->where('created_at', '>=', $today)->count(),
                'open_support_tasks' => (clone $activeTasks)->count(),
                'overdue_support_tasks' => (clone $activeTasks)
                    ->whereNotNull('sla_due_at')->where('sla_due_at', '<=', now())->count(),
                'escalated_support_tasks' => (clone $activeTasks)->where('status', 'escalated')->count(),
                'critical_reports' => (clone $activeTasks)
                    ->where('source_type', 'report')->where('severity', 'critical')->count(),
                'pending_listing_reviews' => Property::query()
                    ->whereIn('review_status', ['submitted', 'under_review'])->count(),
                'pending_verifications' => Schema::hasTable('account_verification_profiles')
                    ? DB::table('account_verification_profiles')->whereIn('status', ['pending', 'needs_more_info'])->count()
                    : 0,
            ],
            'market' => [
                'properties_total' => Property::query()->count(),
                'published_properties' => (clone $published)->count(),
                'published_sale' => (clone $published)->where('purpose', 'sale')->count(),
                'published_rent' => (clone $published)->where('purpose', 'rent')->count(),
                'published_today' => Schema::hasColumn('properties', 'published_at')
                    ? (clone $published)->where('published_at', '>=', $today)->count()
                    : 0,
                'by_type' => $propertyTypes,
                'by_governorate' => $governorates,
                'approved_brokers' => $approvedBrokers,
                'approved_offices' => $approvedOffices,
                'pending_professional_verifications' => $pendingProfessionals,
            ],
            'journey' => $journey,
            'team' => $team,
            'today' => [
                'new_users' => User::query()->where('created_at', '>=', $today)->count(),
                'published_properties' => Schema::hasColumn('properties', 'published_at')
                    ? Property::query()->where('status', 'published')->where('published_at', '>=', $today)->count()
                    : 0,
                'new_support_tasks' => SupportTask::query()->where('created_at', '>=', $today)->count(),
            ],
        ]]);
    }
}
