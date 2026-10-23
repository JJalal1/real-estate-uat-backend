<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $driver = DB::connection()->getDriverName();

        // Keep SQLite tests on native ADD COLUMN operations. Adding a foreign
        // key to an existing SQLite table makes Laravel rebuild the users
        // table, which can flatten Stage 7's partial unique owner index into a
        // plain UNIQUE constraint on is_platform_owner. That would incorrectly
        // allow only one non-owner user. PostgreSQL keeps the real FK.
        Schema::table('users', function (Blueprint $table) use ($driver): void {
            $table->string('account_type', 20)->default('regular')->after('phone')->index();
            $table->unsignedSmallInteger('identity_policy_version')->default(0)->after('account_type');
            $table->string('broker_verification_status', 30)->default('not_required')->after('account_status')->index();
            $table->timestampTz('broker_verification_submitted_at')->nullable()->after('broker_verification_status');
            $table->timestampTz('broker_verified_at')->nullable()->after('broker_verification_submitted_at');

            if ($driver === 'pgsql') {
                $table->foreignId('broker_verified_by_user_id')->nullable()->after('broker_verified_at')->constrained('users')->nullOnDelete();
            } else {
                $table->unsignedBigInteger('broker_verified_by_user_id')->nullable()->after('broker_verified_at');
            }

            $table->text('broker_verification_note')->nullable()->after('broker_verified_by_user_id');
        });

        Schema::create('broker_verification_documents', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('kind', 30);
            $table->string('path', 500);
            $table->string('original_name', 255)->nullable();
            $table->string('mime_type', 120)->nullable();
            $table->unsignedBigInteger('size_bytes')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'kind']);
        });

        $now = now();
        $brokerRoleId = DB::table('roles')->where('key', 'broker')->value('id');
        if ($brokerRoleId) {
            $brokerIds = DB::table('user_role')->where('role_id', $brokerRoleId)->pluck('user_id');
            if ($brokerIds->isNotEmpty()) {
                DB::table('users')->whereIn('id', $brokerIds)->update([
                    'account_type' => 'broker',
                    'broker_verification_status' => 'not_submitted',
                    'broker_verified_at' => null,
                ]);
            }
        }

        if (! DB::table('permissions')->where('key', 'brokers.verify_accounts')->exists()) {
            DB::table('permissions')->insert([
                'key' => 'brokers.verify_accounts',
                'name_ar' => 'توثيق حسابات الدلالين',
                'name_en' => 'Verify broker accounts',
                'scope' => 'brokers',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $verifyPermissionId = DB::table('permissions')->where('key', 'brokers.verify_accounts')->value('id');
        foreach (['support_manager', 'support_agent'] as $roleKey) {
            $roleId = DB::table('roles')->where('key', $roleKey)->value('id');
            if ($roleId && $verifyPermissionId) {
                DB::table('role_permission')->insertOrIgnore([
                    'role_id' => $roleId,
                    'permission_id' => $verifyPermissionId,
                ]);
            }
        }

        // Historical local-broker/cell permission is retained for audit data,
        // but it is no longer granted to the broker role.
        $legacyPermissionId = DB::table('permissions')->where('key', 'listings.verify_local')->value('id');
        if ($brokerRoleId && $legacyPermissionId) {
            DB::table('role_permission')
                ->where('role_id', $brokerRoleId)
                ->where('permission_id', $legacyPermissionId)
                ->delete();
        }

        if ($driver === 'pgsql') {
            DB::statement("ALTER TABLE users ADD CONSTRAINT users_account_type_valid CHECK (account_type IN ('regular','broker'))");
            DB::statement("ALTER TABLE users ADD CONSTRAINT users_broker_verification_status_valid CHECK (broker_verification_status IN ('not_required','not_submitted','pending','approved','rejected'))");
            DB::statement("ALTER TABLE broker_verification_documents ADD CONSTRAINT broker_verification_documents_kind_valid CHECK (kind IN ('id_front','id_back','selfie'))");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_account_type_valid');
            DB::statement('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_broker_verification_status_valid');
            DB::statement('ALTER TABLE broker_verification_documents DROP CONSTRAINT IF EXISTS broker_verification_documents_kind_valid');
        }

        $verifyPermissionId = DB::table('permissions')->where('key', 'brokers.verify_accounts')->value('id');
        if ($verifyPermissionId) {
            DB::table('role_permission')->where('permission_id', $verifyPermissionId)->delete();
            DB::table('user_permission_overrides')->where('permission_id', $verifyPermissionId)->delete();
            DB::table('permissions')->where('id', $verifyPermissionId)->delete();
        }

        $brokerRoleId = DB::table('roles')->where('key', 'broker')->value('id');
        $legacyPermissionId = DB::table('permissions')->where('key', 'listings.verify_local')->value('id');
        if ($brokerRoleId && $legacyPermissionId) {
            DB::table('role_permission')->insertOrIgnore([
                'role_id' => $brokerRoleId,
                'permission_id' => $legacyPermissionId,
            ]);
        }

        Schema::dropIfExists('broker_verification_documents');
        Schema::table('users', function (Blueprint $table) use ($driver): void {
            if ($driver === 'pgsql') {
                $table->dropConstrainedForeignId('broker_verified_by_user_id');
            } else {
                $table->dropColumn('broker_verified_by_user_id');
            }

            $table->dropColumn([
                'account_type',
                'identity_policy_version',
                'broker_verification_status',
                'broker_verification_submitted_at',
                'broker_verified_at',
                'broker_verification_note',
            ]);
        });
    }
};
