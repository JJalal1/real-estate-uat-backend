<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/** One-shot, explicit fixture scope; no public reset endpoint and no global purge. */
class UatWave3CleanupService
{
    private const LEGACY = [
        'uat-regular-1@example.invalid' => '+12025550101',
        'uat-regular-2@example.invalid' => '+12025550102',
        'uat-broker-unverified@example.invalid' => '+12025550103',
        'uat-broker-verified-1@example.invalid' => '+12025550104',
        'uat-broker-verified-2@example.invalid' => '+12025550105',
        'uat-regular-3@example.invalid' => '+12025550110',
        'uat-regular-4@example.invalid' => '+12025550111',
        'uat-regular-5@example.invalid' => '+12025550112',
        'uat-regular-6@example.invalid' => '+12025550113',
    ];

    public function guard(): void
    {
        if (! app()->environment('uat', 'staging', 'testing') || ! config('services.uat_wave3.enabled')) {
            throw new RuntimeException('Wave3 cleanup is explicitly enabled UAT/testing only.');
        }
        if (! app()->environment('testing') && parse_url((string) config('services.supabase_storage.url'), PHP_URL_HOST) !== 'ipxsgxsqzthpgthwvdno.supabase.co') {
            throw new RuntimeException('Wave3 cleanup is restricted to the selected Frankfurt UAT project.');
        }
    }

    public function plan(): array
    {
        $this->guard();
        $ids = [];
        foreach (User::whereIn('email', array_keys(self::LEGACY))->with('roles', 'permissionOverrides')->get() as $user) {
            if ($user->phone !== self::LEGACY[$user->email] || $user->is_platform_owner
                || $user->roles->contains(fn ($role) => ! in_array($role->key, ['registered_user', 'broker'], true))
                || $user->permissionOverrides->contains('effect', 'allow')) continue;
            $ids[] = $user->id;
        }
        $properties = DB::table('properties')->whereIn('user_id', $ids)->pluck('id')->all();
        $assets = DB::table('properties')->whereIn('id', $properties)->whereNotNull('property_asset_id')->pluck('property_asset_id')->unique()->all();
        $assets = array_merge($assets, DB::table('property_assets')->whereIn('created_by_user_id', $ids)->pluck('id')->all());
        $assets = array_values(array_diff(array_unique($assets), DB::table('properties')->whereNotIn('id', $properties)->whereIn('property_asset_id', $assets)->pluck('property_asset_id')->all()));
        if (count($properties) > 100) throw new RuntimeException('Wave3 fixture scope exceeds the reviewed bound.');
        // The inspected legacy UAT has no completed financial/contract history.
        // Fail closed if that changes; never silently erase an unreviewed ledger.
        foreach (['property_deal_financial_terms', 'property_agreements', 'rental_contracts', 'broker_deal_outcomes'] as $table) {
            if (DB::table($table)->whereIn('property_id', $properties)->exists()) throw new RuntimeException('Legacy fixture acquired financial/contract records; cleanup stopped.');
        }
        $threads = DB::table('message_threads')->whereIn('property_id', $properties)->orWhereIn('started_by_user_id', $ids)->pluck('id')->all();
        $bookings = DB::table('viewing_bookings')->whereIn('requester_user_id', $ids)->orWhereIn('host_user_id', $ids)
            ->orWhere(fn ($q) => $q->where('target_type', 'property')->whereIn('target_id', $properties))->pluck('id')->all();
        $cases = DB::table('support_cases')->whereIn('requester_user_id', $ids)
            ->orWhere(fn ($q) => $q->where('target_type', 'property')->whereIn('target_id', $properties))->pluck('id')->all();
        $tasks = DB::table('support_tasks')->whereIn('requester_user_id', $ids)
            ->orWhere(fn ($q) => $q->where('source_type', 'listing_review')->whereIn('source_id', $properties))
            ->orWhere(fn ($q) => $q->where('source_type', 'account_verification')->whereIn('source_id', $ids))
            ->orWhere(fn ($q) => $q->whereIn('source_type', ['support_ticket', 'report'])->whereIn('source_id', $cases))->pluck('id')->all();
        $profiles = DB::table('account_verification_profiles')->whereIn('user_id', $ids)->pluck('id')->all();
        $scope = [];
        $add = function (string $table, string $column, array $values) use (&$scope): void {
            $scope[$table][] = [$column, $values];
        };
        foreach (['property_images', 'property_favorites', 'property_listing_views', 'listing_comments', 'property_sai_terms', 'property_sai_attestations', 'property_identity_checks'] as $table) $add($table, 'property_id', $properties);
        foreach (['listing_reviews', 'listing_broker_verifications'] as $table) $add($table, 'listing_id', $properties);
        foreach (['api_tokens', 'verification_challenges', 'sessions', 'user_role', 'user_permission_overrides', 'user_notification_preferences', 'saved_property_searches', 'broker_verification_documents'] as $table) $add($table, 'user_id', $ids);
        foreach (['private_messages', 'message_thread_participants', 'conversation_reports', 'private_message_access_events'] as $table) $add($table, 'thread_id', $threads);
        $add('listing_documents', 'property_id', $properties);
        $add('broker_cell_assignments', 'broker_user_id', $ids);
        $add('broker_customer_followups', 'message_thread_id', $threads);
        $add('viewing_booking_events', 'viewing_booking_id', $bookings);
        $add('viewing_bookings', 'id', $bookings);
        $add('support_case_messages', 'support_case_id', $cases);
        $add('support_case_events', 'support_case_id', $cases);
        $add('support_task_events', 'support_task_id', $tasks);
        $add('support_tasks', 'id', $tasks);
        $add('support_cases', 'id', $cases);
        $add('account_verification_documents', 'profile_id', $profiles);
        $add('account_verification_profiles', 'id', $profiles);
        $add('advertiser_ratings', 'advertiser_user_id', $ids);
        $add('advertiser_ratings', 'rater_user_id', $ids);
        $add('property_representation_claims', 'advertiser_user_id', $ids);
        $add('property_representation_claims', 'property_id', $properties);
        $add('property_publication_blocks', 'property_asset_id', $assets);
        $add('message_threads', 'id', $threads);
        $add('properties', 'id', $properties);
        $add('property_assets', 'id', $assets);
        $add('user_notifications', 'user_id', $ids);
        $add('audit_logs', 'actor_user_id', $ids);
        $add('audit_logs', 'target_user_id', $ids);
        $add('password_reset_tokens', 'email', DB::table('users')->whereIn('id', $ids)->pluck('email')->all());
        $add('users', 'id', $ids);
        $entities = ['property' => $properties, 'listing' => $properties, 'message_thread' => $threads,
            'viewing_booking' => $bookings, 'support_task' => $tasks, 'support_case' => $cases, 'account_verification' => $ids];
        return compact('ids', 'scope', 'entities');
    }

    public function rows(array $plan, string $table)
    {
        return DB::table($table)->where(function ($query) use ($plan, $table): void {
            foreach ($plan['scope'][$table] as [$column, $values]) $query->orWhereIn($column, $values);
            if ($table === 'user_notifications') {
                foreach ($plan['entities'] as $type => $ids) $query->orWhere(fn ($q) => $q->where('entity_type', $type)->whereIn('entity_id', $ids));
            }
        });
    }

    public function execute(array $plan): array
    {
        $this->guard();
        if (DB::transactionLevel() < 1) throw new RuntimeException('Wave3 cleanup requires the enclosing seed transaction.');
        $backup = [];
        $counts = [];
        foreach (array_keys($plan['scope']) as $table) {
            $rows = $this->rows($plan, $table)->get()->map(fn ($row) => (array) $row)->all();
            $counts[$table] = count($rows);
            // Old authentication credentials are invalidated, not copied.
            if (in_array($table, ['api_tokens', 'verification_challenges', 'sessions', 'password_reset_tokens'], true)) continue;
            foreach ($rows as &$row) unset($row['password'], $row['remember_token']);
            unset($row);
            $backup[$table] = $rows;
        }
        $json = json_encode(['version' => 3, 'created_at' => now()->toIso8601String(), 'counts' => $counts, 'rows' => $backup], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        $temp = tempnam(sys_get_temp_dir(), 'uat-wave3-backup-');
        try {
            file_put_contents($temp, $json);
            $path = app(CloudAssetStorageService::class)->storePrivate(new UploadedFile($temp, 'uat-wave3-backup.json', 'application/json', null, true), 'uat-wave3/backups');
            if (! app(CloudAssetStorageService::class)->existsPrivate($path)) throw new RuntimeException('Private UAT backup verification failed.');
        } finally {
            if (is_file($temp)) unlink($temp);
        }
        $driver = DB::connection()->getDriverName();
        $triggers = $driver === 'pgsql'
            ? DB::select("SELECT c.relname AS table_name,t.tgname AS name,pg_get_triggerdef(t.oid) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal AND t.tgname LIKE '%immutable_delete'")
            : DB::select("SELECT tbl_name AS table_name,name,sql AS definition FROM sqlite_master WHERE type='trigger' AND name LIKE '%immutable_delete'");
        $removed = [];
        foreach ($triggers as $trigger) {
            if (! ($counts[$trigger->table_name] ?? 0)) continue;
            DB::statement('DROP TRIGGER "'.$trigger->name.'"'.($driver === 'pgsql' ? ' ON "'.$trigger->table_name.'"' : ''));
            $removed[] = $trigger;
        }
        // No FK/RLS is disabled. Scoped children are deleted before their parent.
        $order = ['broker_customer_followups', 'private_message_access_events', 'conversation_reports', 'private_messages', 'message_thread_participants',
            'viewing_booking_events', 'viewing_bookings', 'support_task_events', 'support_tasks', 'support_case_events', 'support_case_messages', 'support_cases',
            'account_verification_documents', 'account_verification_profiles', 'advertiser_ratings', 'listing_broker_verifications', 'listing_comments',
            'listing_documents', 'listing_reviews', 'property_identity_checks', 'property_representation_claims', 'property_publication_blocks',
            'property_images', 'property_favorites', 'property_listing_views', 'message_threads', 'properties', 'property_sai_attestations', 'property_sai_terms', 'property_assets',
            'user_notifications', 'audit_logs', 'api_tokens', 'verification_challenges', 'sessions', 'password_reset_tokens', 'user_notification_preferences',
            'saved_property_searches', 'broker_verification_documents', 'broker_cell_assignments', 'user_permission_overrides', 'user_role', 'users'];
        foreach ($order as $table) $this->rows($plan, $table)->delete();
        foreach ($removed as $trigger) DB::statement($trigger->definition);
        return ['counts' => $counts, 'private_backup' => $path, 'backup_sha256' => hash('sha256', $json)];
    }
}
