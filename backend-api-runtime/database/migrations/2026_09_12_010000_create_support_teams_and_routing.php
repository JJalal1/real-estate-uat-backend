<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('support_teams')) {
            Schema::create('support_teams', function (Blueprint $table): void {
                $table->id();
                $table->string('code', 80)->unique();
                $table->string('name_ar', 160);
                $table->foreignId('governorate_id')->nullable()->constrained('governorates')->nullOnDelete();
                $table->foreignId('manager_user_id')->nullable()->constrained('users')->nullOnDelete();
                $table->boolean('is_fallback')->default(false)->index();
                $table->boolean('is_active')->default(true)->index();
                $table->timestamps();
                $table->index(['governorate_id', 'is_active'], 'support_teams_governorate_active_idx');
            });
        }

        if (! Schema::hasTable('support_team_members')) {
            Schema::create('support_team_members', function (Blueprint $table): void {
                $table->id();
                $table->foreignId('support_team_id')->constrained('support_teams')->cascadeOnDelete();
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->string('member_role', 24)->default('agent');
                $table->boolean('is_available')->default(true)->index();
                $table->unsignedSmallInteger('capacity')->default(10);
                $table->timestamp('joined_at')->nullable();
                $table->timestamps();
                $table->unique(['support_team_id', 'user_id'], 'support_team_members_team_user_unique');
                $table->index(['user_id', 'is_available'], 'support_team_members_user_available_idx');
            });
        }

        Schema::table('support_tasks', function (Blueprint $table): void {
            if (! Schema::hasColumn('support_tasks', 'support_team_id')) {
                $table->foreignId('support_team_id')->nullable()->after('severity')->constrained('support_teams')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'governorate_id')) {
                $table->foreignId('governorate_id')->nullable()->after('support_team_id')->constrained('governorates')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_by_user_id')) {
                $table->foreignId('escalated_by_user_id')->nullable()->after('assigned_to_name_snapshot')->constrained('users')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_at')) {
                $table->timestamp('escalated_at')->nullable()->after('escalated_by_user_id')->index();
            }
            if (! Schema::hasColumn('support_tasks', 'escalation_reason')) {
                $table->text('escalation_reason')->nullable()->after('escalated_at');
            }
            if (! Schema::hasColumn('support_tasks', 'completed_at')) {
                $table->timestamp('completed_at')->nullable()->after('last_activity_at')->index();
            }
        });

        if (! $this->hasIndex('support_tasks', 'support_tasks_team_status_idx')) {
            Schema::table('support_tasks', function (Blueprint $table): void {
                $table->index(['support_team_id', 'status', 'priority'], 'support_tasks_team_status_idx');
            });
        }

        $managerId = DB::table('user_role as ur')
            ->join('roles as r', 'r.id', '=', 'ur.role_id')
            ->where('r.key', 'support_manager')
            ->orderBy('ur.user_id')
            ->value('ur.user_id');
        $now = now();

        DB::table('support_teams')->upsert([[
            'code' => 'general-support',
            'name_ar' => 'فريق الدعم العام',
            'governorate_id' => null,
            'manager_user_id' => $managerId,
            'is_fallback' => true,
            'is_active' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ]], ['code'], ['name_ar', 'manager_user_id', 'is_fallback', 'is_active', 'updated_at']);

        if (Schema::hasTable('governorates')) {
            $rows = DB::table('governorates')->where('is_active', true)->orderBy('id')->get();
            $teams = [];
            foreach ($rows as $row) {
                $teams[] = [
                    'code' => 'gov-'.$row->code,
                    'name_ar' => 'دعم '.$row->name_ar,
                    'governorate_id' => $row->id,
                    'manager_user_id' => $managerId,
                    'is_fallback' => false,
                    'is_active' => true,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            if ($teams !== []) {
                DB::table('support_teams')->upsert(
                    $teams,
                    ['code'],
                    ['name_ar', 'governorate_id', 'manager_user_id', 'is_active', 'updated_at']
                );
            }
        }

        $fallbackId = DB::table('support_teams')->where('code', 'general-support')->value('id');
        if ($fallbackId) {
            $staff = DB::table('user_role as ur')
                ->join('roles as r', 'r.id', '=', 'ur.role_id')
                ->whereIn('r.key', ['support_agent', 'support_manager'])
                ->select('ur.user_id', 'r.key')
                ->orderBy('ur.user_id')
                ->get()
                ->groupBy('user_id');
            $members = [];
            foreach ($staff as $userId => $roles) {
                $roleKeys = $roles->pluck('key');
                $members[] = [
                    'support_team_id' => $fallbackId,
                    'user_id' => $userId,
                    'member_role' => $roleKeys->contains('support_manager') ? 'manager' : 'agent',
                    'is_available' => true,
                    'capacity' => 10,
                    'joined_at' => $now,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            if ($members !== []) {
                DB::table('support_team_members')->upsert(
                    $members,
                    ['support_team_id', 'user_id'],
                    ['member_role', 'is_available', 'capacity', 'updated_at']
                );
            }
            DB::table('support_tasks')->whereNull('support_team_id')->update([
                'support_team_id' => $fallbackId,
                'updated_at' => $now,
            ]);
        }
        DB::table('support_tasks')
            ->whereIn('status', ['completed', 'rejected'])
            ->whereNull('completed_at')
            ->update(['completed_at' => DB::raw('updated_at')]);

        if (DB::getDriverName() === 'pgsql') {
            foreach (['support_teams', 'support_team_members'] as $table) {
                DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");
                DB::statement("REVOKE ALL ON TABLE {$table} FROM PUBLIC");
                DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM anon'; END IF; IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE {$table} FROM authenticated'; END IF; END $$;");
            }
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('support_tasks')) {
            Schema::table('support_tasks', function (Blueprint $table): void {
                foreach (['support_team_id', 'governorate_id', 'escalated_by_user_id'] as $column) {
                    if (Schema::hasColumn('support_tasks', $column)) {
                        $table->dropConstrainedForeignId($column);
                    }
                }
                foreach (['escalated_at', 'escalation_reason', 'completed_at'] as $column) {
                    if (Schema::hasColumn('support_tasks', $column)) $table->dropColumn($column);
                }
            });
        }
        Schema::dropIfExists('support_team_members');
        Schema::dropIfExists('support_teams');
    }

    private function hasIndex(string $table, string $name): bool
    {
        if (DB::getDriverName() !== 'pgsql') return false;
        return DB::table('pg_indexes')
            ->where('schemaname', 'public')
            ->where('tablename', $table)
            ->where('indexname', $name)
            ->exists();
    }
};
