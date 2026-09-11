from pathlib import Path
p=Path('backend-api-runtime/database/migrations/2026_09_12_010000_create_support_teams_and_routing.php')
s=p.read_text()
old="""                $table->foreignId('manager_user_id')->nullable()->constrained('users')->nullOnDelete();
                $table->boolean('is_fallback')->default(false)->index();
"""
new="""                $table->foreignId('manager_user_id')->nullable()->constrained('users')->nullOnDelete();
                $table->index('manager_user_id', 'support_teams_manager_user_idx');
                $table->boolean('is_fallback')->default(false)->index();
"""
if old not in s: raise SystemExit('support teams manager FK pattern missing')
s=s.replace(old,new,1)
old="""            if (! Schema::hasColumn('support_tasks', 'governorate_id')) {
                $table->foreignId('governorate_id')->nullable()->after('support_team_id')->constrained('governorates')->nullOnDelete();
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_by_user_id')) {
                $table->foreignId('escalated_by_user_id')->nullable()->after('assigned_to_name_snapshot')->constrained('users')->nullOnDelete();
            }
"""
new="""            if (! Schema::hasColumn('support_tasks', 'governorate_id')) {
                $table->foreignId('governorate_id')->nullable()->after('support_team_id')->constrained('governorates')->nullOnDelete();
                $table->index('governorate_id', 'support_tasks_governorate_idx');
            }
            if (! Schema::hasColumn('support_tasks', 'escalated_by_user_id')) {
                $table->foreignId('escalated_by_user_id')->nullable()->after('assigned_to_name_snapshot')->constrained('users')->nullOnDelete();
                $table->index('escalated_by_user_id', 'support_tasks_escalated_by_idx');
            }
"""
if old not in s: raise SystemExit('support task FK patterns missing')
s=s.replace(old,new,1)
p.write_text(s)
print('support FK indexes added')
