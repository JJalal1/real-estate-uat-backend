<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class GeneralManagerDashboardController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        /** @var User|null $actor */
        $actor = $request->user();
        if (! $actor || ! ($actor->is_platform_owner || $actor->hasRole('super_admin'))) {
            abort(403);
        }

        $data = app()->environment('testing')
            ? $this->build()
            : Cache::remember('general-manager:insights:v3', now()->addSeconds(30), fn () => $this->build());

        return response()->json(['data' => $data]);
    }

    private function build(): array
    {
        return DB::connection()->getDriverName() === 'pgsql'
            ? $this->buildPostgres()
            : $this->buildPortable();
    }

    private function buildPostgres(): array
    {
        $row = DB::selectOne(<<<'SQL'
WITH params AS (
    SELECT CURRENT_DATE::timestamp AS today_start,
           (CURRENT_TIMESTAMP - INTERVAL '7 days') AS week_start,
           (CURRENT_TIMESTAMP - INTERVAL '30 days') AS month_start
)
SELECT
 (SELECT COUNT(*) FROM users) users_total,
 (SELECT COUNT(*) FROM users WHERE created_at >= (SELECT today_start FROM params)) users_new_today,
 (SELECT COUNT(*) FROM users WHERE created_at >= (SELECT week_start FROM params)) users_new_7d,
 (SELECT COUNT(*) FROM users WHERE created_at >= (SELECT month_start FROM params)) users_new_30d,
 (SELECT COUNT(*) FROM support_tasks WHERE status IN ('new','in_progress','waiting_user','waiting_internal','needs_followup','escalated')) open_support_tasks,
 (SELECT COUNT(*) FROM support_tasks WHERE status IN ('new','in_progress','waiting_user','waiting_internal','needs_followup','escalated') AND sla_due_at IS NOT NULL AND sla_due_at <= CURRENT_TIMESTAMP) overdue_support_tasks,
 (SELECT COUNT(*) FROM support_tasks WHERE status='escalated') escalated_support_tasks,
 (SELECT COUNT(*) FROM support_tasks WHERE status IN ('new','in_progress','waiting_user','waiting_internal','needs_followup','escalated') AND source_type='report' AND severity='critical') critical_reports,
 (SELECT COUNT(*) FROM support_tasks WHERE created_at >= (SELECT today_start FROM params)) support_tasks_today,
 (SELECT COUNT(*) FROM support_tasks WHERE created_at >= (SELECT week_start FROM params)) support_tasks_7d,
 (SELECT COUNT(*) FROM support_tasks WHERE created_at >= (SELECT month_start FROM params)) support_tasks_30d,
 (SELECT COUNT(*) FROM properties) properties_total,
 (SELECT COUNT(*) FROM properties WHERE status='published') published_properties,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND purpose='sale') published_sale,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND purpose='rent') published_rent,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND published_at >= (SELECT today_start FROM params)) published_today,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND published_at >= (SELECT week_start FROM params)) published_7d,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND published_at >= (SELECT month_start FROM params)) published_30d,
 (SELECT COUNT(*) FROM properties WHERE status='published' AND geo_cell_id IS NULL) unmapped_published,
 (SELECT COUNT(*) FROM properties WHERE review_status IN ('submitted','under_review')) pending_listing_reviews,
 (SELECT COUNT(*) FROM account_verification_profiles WHERE status IN ('pending','needs_more_info')) pending_verifications,
 (SELECT COUNT(*) FROM account_verification_profiles WHERE type='broker' AND status='approved') approved_brokers,
 (SELECT COUNT(*) FROM account_verification_profiles WHERE type='office' AND status='approved') approved_offices,
 (SELECT COUNT(*) FROM account_verification_profiles WHERE type IN ('broker','office') AND status IN ('pending','needs_more_info')) pending_professional_verifications,
 (SELECT COUNT(DISTINCT ur.user_id) FROM user_role ur JOIN roles r ON r.id=ur.role_id JOIN users u ON u.id=ur.user_id WHERE r.key='support_agent' AND u.account_status='active') support_agents,
 (SELECT COUNT(DISTINCT ur.user_id) FROM user_role ur JOIN roles r ON r.id=ur.role_id JOIN users u ON u.id=ur.user_id WHERE r.key='support_manager' AND u.account_status='active') support_managers,
 (SELECT COUNT(*) FROM message_threads) conversations,
 (SELECT COUNT(*) FROM viewing_bookings) viewings,
 (SELECT COUNT(*) FROM property_agreements) agreements,
 (SELECT COUNT(*) FROM rental_contracts) rental_contracts,
 (SELECT COUNT(*) FROM governorates) governorates_total,
 (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',x.type,'total',x.total) ORDER BY x.total DESC),'[]'::jsonb) FROM (SELECT type,COUNT(*)::int total FROM properties WHERE status='published' GROUP BY type)x) property_types,
 (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name_ar,'total',x.total,'sale',x.sale,'rent',x.rent) ORDER BY x.total DESC),'[]'::jsonb) FROM (SELECT g.id,g.name_ar,COUNT(*)::int total,COUNT(*) FILTER(WHERE p.purpose='sale')::int sale,COUNT(*) FILTER(WHERE p.purpose='rent')::int rent FROM properties p JOIN geo_cells c ON c.id=p.geo_cell_id JOIN governorates g ON g.id=c.governorate_id WHERE p.status='published' GROUP BY g.id,g.name_ar ORDER BY total DESC LIMIT 30)x) governorates,
 (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',x.id,'title',x.title,'purpose',x.purpose,'type',x.type,'latitude',x.latitude,'longitude',x.longitude) ORDER BY x.id DESC),'[]'::jsonb) FROM (SELECT id,title,purpose,type,latitude,longitude FROM properties WHERE status='published' AND latitude IS NOT NULL AND longitude IS NOT NULL ORDER BY id DESC LIMIT 500)x) map_properties
SQL);

        return $this->shape([
            'users_total'=>(int)$row->users_total,'users_new_today'=>(int)$row->users_new_today,'users_new_7d'=>(int)$row->users_new_7d,'users_new_30d'=>(int)$row->users_new_30d,
            'open_support_tasks'=>(int)$row->open_support_tasks,'overdue_support_tasks'=>(int)$row->overdue_support_tasks,'escalated_support_tasks'=>(int)$row->escalated_support_tasks,'critical_reports'=>(int)$row->critical_reports,
            'support_tasks_today'=>(int)$row->support_tasks_today,'support_tasks_7d'=>(int)$row->support_tasks_7d,'support_tasks_30d'=>(int)$row->support_tasks_30d,
            'properties_total'=>(int)$row->properties_total,'published_properties'=>(int)$row->published_properties,'published_sale'=>(int)$row->published_sale,'published_rent'=>(int)$row->published_rent,
            'published_today'=>(int)$row->published_today,'published_7d'=>(int)$row->published_7d,'published_30d'=>(int)$row->published_30d,'unmapped_published'=>(int)$row->unmapped_published,
            'pending_listing_reviews'=>(int)$row->pending_listing_reviews,'pending_verifications'=>(int)$row->pending_verifications,'approved_brokers'=>(int)$row->approved_brokers,'approved_offices'=>(int)$row->approved_offices,
            'pending_professional_verifications'=>(int)$row->pending_professional_verifications,'support_agents'=>(int)$row->support_agents,'support_managers'=>(int)$row->support_managers,
            'conversations'=>(int)$row->conversations,'viewings'=>(int)$row->viewings,'agreements'=>(int)$row->agreements,'rental_contracts'=>(int)$row->rental_contracts,'governorates_total'=>(int)$row->governorates_total,
            'by_type'=>$this->jsonArray($row->property_types ?? null),'by_governorate'=>$this->jsonArray($row->governorates ?? null),'map_properties'=>$this->jsonArray($row->map_properties ?? null),
        ]);
    }

    private function buildPortable(): array
    {
        $count = fn (string $table): ?int => Schema::hasTable($table) ? DB::table($table)->count() : null;
        $today = now()->startOfDay();
        $week = now()->subDays(7);
        $month = now()->subDays(30);
        $published = DB::table('properties')->where('status', 'published');
        $active = DB::table('support_tasks')->whereIn('status', ['new','in_progress','waiting_user','waiting_internal','needs_followup','escalated']);

        return $this->shape([
            'users_total'=>DB::table('users')->count(),'users_new_today'=>DB::table('users')->where('created_at','>=',$today)->count(),'users_new_7d'=>DB::table('users')->where('created_at','>=',$week)->count(),'users_new_30d'=>DB::table('users')->where('created_at','>=',$month)->count(),
            'open_support_tasks'=>(clone $active)->count(),'overdue_support_tasks'=>(clone $active)->whereNotNull('sla_due_at')->where('sla_due_at','<=',now())->count(),'escalated_support_tasks'=>(clone $active)->where('status','escalated')->count(),'critical_reports'=>(clone $active)->where('source_type','report')->where('severity','critical')->count(),
            'support_tasks_today'=>DB::table('support_tasks')->where('created_at','>=',$today)->count(),'support_tasks_7d'=>DB::table('support_tasks')->where('created_at','>=',$week)->count(),'support_tasks_30d'=>DB::table('support_tasks')->where('created_at','>=',$month)->count(),
            'properties_total'=>DB::table('properties')->count(),'published_properties'=>(clone $published)->count(),'published_sale'=>(clone $published)->where('purpose','sale')->count(),'published_rent'=>(clone $published)->where('purpose','rent')->count(),'published_today'=>(clone $published)->where('published_at','>=',$today)->count(),'published_7d'=>(clone $published)->where('published_at','>=',$week)->count(),'published_30d'=>(clone $published)->where('published_at','>=',$month)->count(),'unmapped_published'=>Schema::hasColumn('properties','geo_cell_id')?(clone $published)->whereNull('geo_cell_id')->count():0,
            'pending_listing_reviews'=>DB::table('properties')->whereIn('review_status',['submitted','under_review'])->count(),'pending_verifications'=>Schema::hasTable('account_verification_profiles')?DB::table('account_verification_profiles')->whereIn('status',['pending','needs_more_info'])->count():0,'approved_brokers'=>Schema::hasTable('account_verification_profiles')?DB::table('account_verification_profiles')->where('type','broker')->where('status','approved')->count():0,'approved_offices'=>Schema::hasTable('account_verification_profiles')?DB::table('account_verification_profiles')->where('type','office')->where('status','approved')->count():0,'pending_professional_verifications'=>Schema::hasTable('account_verification_profiles')?DB::table('account_verification_profiles')->whereIn('type',['broker','office'])->whereIn('status',['pending','needs_more_info'])->count():0,
            'support_agents'=>0,'support_managers'=>0,'conversations'=>$count('message_threads'),'viewings'=>$count('viewing_bookings'),'agreements'=>$count('property_agreements'),'rental_contracts'=>$count('rental_contracts'),'governorates_total'=>$count('governorates') ?? 0,'by_type'=>[],'by_governorate'=>[],'map_properties'=>[],
        ]);
    }

    private function shape(array $m): array
    {
        return [
            'mode'=>'general_manager',
            'overview'=>['users_total'=>$m['users_total'],'users_new_today'=>$m['users_new_today'],'open_support_tasks'=>$m['open_support_tasks'],'overdue_support_tasks'=>$m['overdue_support_tasks'],'escalated_support_tasks'=>$m['escalated_support_tasks'],'critical_reports'=>$m['critical_reports'],'pending_listing_reviews'=>$m['pending_listing_reviews'],'pending_verifications'=>$m['pending_verifications']],
            'market'=>['properties_total'=>$m['properties_total'],'published_properties'=>$m['published_properties'],'published_sale'=>$m['published_sale'],'published_rent'=>$m['published_rent'],'published_today'=>$m['published_today'],'unmapped_published'=>$m['unmapped_published'],'governorates_total'=>$m['governorates_total'],'by_type'=>$m['by_type'],'by_governorate'=>$m['by_governorate'],'map_properties'=>$m['map_properties'],'approved_brokers'=>$m['approved_brokers'],'approved_offices'=>$m['approved_offices'],'pending_professional_verifications'=>$m['pending_professional_verifications']],
            'journey'=>['conversations'=>$m['conversations'],'viewings'=>$m['viewings'],'agreements'=>$m['agreements'],'rental_contracts'=>$m['rental_contracts']],
            'team'=>['support_agents'=>$m['support_agents'],'support_managers'=>$m['support_managers']],
            'today'=>['new_users'=>$m['users_new_today'],'published_properties'=>$m['published_today'],'new_support_tasks'=>$m['support_tasks_today']],
            'periods'=>['day'=>['new_users'=>$m['users_new_today'],'published_properties'=>$m['published_today'],'new_support_tasks'=>$m['support_tasks_today']], '7d'=>['new_users'=>$m['users_new_7d'],'published_properties'=>$m['published_7d'],'new_support_tasks'=>$m['support_tasks_7d']], '30d'=>['new_users'=>$m['users_new_30d'],'published_properties'=>$m['published_30d'],'new_support_tasks'=>$m['support_tasks_30d']]],
        ];
    }

    private function jsonArray(mixed $value): array
    {
        if (is_array($value)) return $value;
        if (is_string($value)) {
            $decoded = json_decode($value, true);
            return is_array($decoded) ? $decoded : [];
        }
        return [];
    }
}
