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

        Schema::table('users', function (Blueprint $table): void {
            $table->timestampTz('profile_completed_at')->nullable()->after('phone_verified_at');
        });

        Schema::create('account_verification_profiles', function (Blueprint $table) use ($driver): void {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained('users')->cascadeOnDelete();
            $table->string('type', 20);
            $table->string('status', 30)->default('not_submitted')->index();
            $table->json('details')->nullable();
            $table->timestampTz('submitted_at')->nullable();
            $table->timestampTz('reviewed_at')->nullable();
            if ($driver === 'pgsql') {
                $table->foreignId('reviewed_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            } else {
                $table->unsignedBigInteger('reviewed_by_user_id')->nullable();
            }
            $table->text('review_note')->nullable();
            $table->timestamps();
        });

        Schema::create('account_verification_documents', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('profile_id')->constrained('account_verification_profiles')->cascadeOnDelete();
            $table->string('kind', 60);
            $table->string('path', 500);
            $table->string('original_name', 255)->nullable();
            $table->string('mime_type', 120)->nullable();
            $table->unsignedBigInteger('size_bytes')->nullable();
            $table->timestamps();
            $table->unique(['profile_id', 'kind']);
        });

        Schema::table('properties', function (Blueprint $table): void {
            $table->string('ownership_document_type', 40)->nullable()->after('contact_whatsapp');
            $table->string('document_owner_name', 160)->nullable()->after('ownership_document_type');
            $table->string('owner_relationship_type', 30)->nullable()->after('document_owner_name');
            $table->string('owner_relationship_note', 255)->nullable()->after('owner_relationship_type');
        });

        // Existing accounts predate the new unified onboarding flow. Do not force
        // them to re-enter their name merely because this migration was deployed.
        DB::table('users')->whereNull('profile_completed_at')->update([
            'profile_completed_at' => now(),
        ]);

        // Preserve successfully established broker KYC as a compatibility baseline.
        // Pending/not-submitted brokers may resubmit using the new richer profile form.
        $brokers = DB::table('users')->where('account_type', 'broker')->get();
        foreach ($brokers as $broker) {
            $status = match ((string) ($broker->broker_verification_status ?? 'not_submitted')) {
                'approved' => 'approved',
                'pending' => 'pending',
                'rejected' => 'rejected',
                default => 'not_submitted',
            };

            $profileId = DB::table('account_verification_profiles')->insertGetId([
                'user_id' => $broker->id,
                'type' => 'broker',
                'status' => $status,
                'details' => json_encode([
                    'legacy_broker_kyc_migrated' => true,
                ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'submitted_at' => $broker->broker_verification_submitted_at ?? null,
                'reviewed_at' => $broker->broker_verified_at ?? null,
                'reviewed_by_user_id' => $broker->broker_verified_by_user_id ?? null,
                'review_note' => $broker->broker_verification_note ?? null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $kindMap = [
                'id_front' => 'identity_document',
                'id_back' => 'identity_back',
                'selfie' => 'selfie',
            ];
            $legacyDocuments = DB::table('broker_verification_documents')->where('user_id', $broker->id)->get();
            foreach ($legacyDocuments as $document) {
                $kind = $kindMap[$document->kind] ?? null;
                if ($kind === null) continue;
                DB::table('account_verification_documents')->insert([
                    'profile_id' => $profileId,
                    'kind' => $kind,
                    'path' => $document->path,
                    'original_name' => $document->original_name,
                    'mime_type' => $document->mime_type,
                    'size_bytes' => $document->size_bytes,
                    'created_at' => $document->created_at ?? now(),
                    'updated_at' => $document->updated_at ?? now(),
                ]);
            }
        }

        $now = now();
        if (! DB::table('permissions')->where('key', 'accounts.verify_profiles')->exists()) {
            DB::table('permissions')->insert([
                'key' => 'accounts.verify_profiles',
                'name_ar' => 'مراجعة توثيق أنواع الحسابات',
                'name_en' => 'Review account verification profiles',
                'scope' => 'accounts',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $permissionId = DB::table('permissions')->where('key', 'accounts.verify_profiles')->value('id');
        foreach (['platform_admin', 'support_manager', 'support_agent'] as $roleKey) {
            $roleId = DB::table('roles')->where('key', $roleKey)->value('id');
            if ($roleId && $permissionId) {
                DB::table('role_permission')->insertOrIgnore([
                    'role_id' => $roleId,
                    'permission_id' => $permissionId,
                ]);
            }
        }

        if ($driver === 'pgsql') {
            DB::statement("ALTER TABLE account_verification_profiles ADD CONSTRAINT account_verification_profiles_type_valid CHECK (type IN ('owner','broker','office'))");
            DB::statement("ALTER TABLE account_verification_profiles ADD CONSTRAINT account_verification_profiles_status_valid CHECK (status IN ('not_submitted','pending','approved','rejected','needs_more_info'))");
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_owner_relationship_type_valid CHECK (owner_relationship_type IS NULL OR owner_relationship_type IN ('owner','agent','heir','co_owner','other'))");
            DB::statement("ALTER TABLE properties ADD CONSTRAINT properties_ownership_document_type_valid CHECK (ownership_document_type IS NULL OR ownership_document_type IN ('purchase_deed','registry_record','partition_deed','court_judgment','inheritance_document','ownership_contract','other'))");
        }
    }

    public function down(): void
    {
        $driver = DB::connection()->getDriverName();
        if ($driver === 'pgsql') {
            DB::statement('ALTER TABLE account_verification_profiles DROP CONSTRAINT IF EXISTS account_verification_profiles_type_valid');
            DB::statement('ALTER TABLE account_verification_profiles DROP CONSTRAINT IF EXISTS account_verification_profiles_status_valid');
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_owner_relationship_type_valid');
            DB::statement('ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_ownership_document_type_valid');
        }

        $permissionId = DB::table('permissions')->where('key', 'accounts.verify_profiles')->value('id');
        if ($permissionId) {
            DB::table('role_permission')->where('permission_id', $permissionId)->delete();
            DB::table('user_permission_overrides')->where('permission_id', $permissionId)->delete();
            DB::table('permissions')->where('id', $permissionId)->delete();
        }

        Schema::table('properties', function (Blueprint $table): void {
            $table->dropColumn([
                'ownership_document_type',
                'document_owner_name',
                'owner_relationship_type',
                'owner_relationship_note',
            ]);
        });
        Schema::dropIfExists('account_verification_documents');
        Schema::dropIfExists('account_verification_profiles');
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn('profile_completed_at');
        });
    }
};
