<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('platform_settings', function (Blueprint $table): void {
            $table->id();
            $table->string('key', 120)->unique();
            $table->text('value')->nullable();
            $table->string('value_type', 20)->default('string');
            $table->string('group_key', 60)->default('general')->index();
            $table->string('label_ar', 180);
            $table->boolean('is_public')->default(false);
            $table->unsignedBigInteger('updated_by_user_id')->nullable()->index();
            $table->timestamps();
        });

        $now = now();
        foreach ([
            ['key'=>'platform.name','value'=>'منصة العقارات','value_type'=>'string','group_key'=>'general','label_ar'=>'اسم المنصة'],
            ['key'=>'platform.contact_phone','value'=>'','value_type'=>'string','group_key'=>'general','label_ar'=>'رقم التواصل'],
            ['key'=>'platform.contact_email','value'=>'','value_type'=>'string','group_key'=>'general','label_ar'=>'بريد التواصل'],
            ['key'=>'listings.review_warning_hours','value'=>'24','value_type'=>'integer','group_key'=>'listings','label_ar'=>'التنبيه على إعلان ينتظر المراجعة بعد (ساعة)'],
            ['key'=>'support.sla_hours','value'=>'48','value_type'=>'integer','group_key'=>'support','label_ar'=>'مدة الاستجابة للدعم بالساعات'],
            ['key'=>'support.sla_warning_hours','value'=>'6','value_type'=>'integer','group_key'=>'support','label_ar'=>'التنبيه قبل تجاوز مدة الاستجابة بالساعات'],
            ['key'=>'notifications.dashboard_alerts_enabled','value'=>'true','value_type'=>'boolean','group_key'=>'notifications','label_ar'=>'إظهار تنبيهات الإدارة في لوحة التحكم'],
        ] as $row) {
            DB::table('platform_settings')->insert($row + ['is_public'=>false,'created_at'=>$now,'updated_at'=>$now]);
        }

        if (! DB::table('roles')->where('key', 'platform_admin')->exists()) {
            DB::table('roles')->insert([
                'key'=>'platform_admin','name_ar'=>'مدير','name_en'=>'Platform Admin','is_system'=>true,'created_at'=>$now,'updated_at'=>$now,
            ]);
        }

        $permissions = [
            ['key'=>'dashboard.view','name_ar'=>'عرض لوحة الإدارة','name_en'=>'View administration dashboard','scope'=>'dashboard'],
            ['key'=>'settings.view','name_ar'=>'عرض إعدادات المنصة','name_en'=>'View platform settings','scope'=>'settings'],
            ['key'=>'settings.manage','name_ar'=>'تعديل إعدادات المنصة','name_en'=>'Manage platform settings','scope'=>'settings'],
            ['key'=>'support.reassign','name_ar'=>'إعادة إسناد حالات الدعم','name_en'=>'Reassign support cases','scope'=>'support'],
            ['key'=>'support.escalate','name_ar'=>'تصعيد حالات الدعم','name_en'=>'Escalate support cases','scope'=>'support'],
            ['key'=>'support.reopen','name_ar'=>'إعادة فتح حالات الدعم','name_en'=>'Reopen support cases','scope'=>'support'],
            ['key'=>'support.view_team_metrics','name_ar'=>'عرض إحصائيات فريق الدعم','name_en'=>'View support team metrics','scope'=>'support'],
            ['key'=>'support.view_worklog','name_ar'=>'عرض سجل عمل الدعم','name_en'=>'View support work log','scope'=>'support'],
        ];
        foreach ($permissions as $permission) {
            DB::table('permissions')->updateOrInsert(
                ['key'=>$permission['key']],
                $permission + ['created_at'=>$now,'updated_at'=>$now],
            );
        }

        $permissionIds = DB::table('permissions')->pluck('id', 'key');
        $roleIds = DB::table('roles')->pluck('id', 'key');
        $map = [
            'platform_admin' => [
                'dashboard.view','settings.view','users.view','users.manage_status','audit.view',
                'support.handle_reports','support.manage','support.reassign','support.escalate','support.reopen','support.view_team_metrics','support.view_worklog',
                'content.moderate','listings.moderate','listings.manage_blocks','regions.manage','bookings.manage',
                'services.manage','developments.manage','developments.publish','brokers.verify_accounts',
            ],
            'support_manager' => [
                'support.reassign','support.escalate','support.reopen','support.view_team_metrics','support.view_worklog',
            ],
            'support_agent' => ['support.escalate','support.view_worklog'],
            'permissions_manager' => ['dashboard.view','settings.view'],
            'regions_manager' => ['dashboard.view'],
            'content_moderator' => ['dashboard.view'],
        ];
        foreach ($map as $roleKey => $keys) {
            if (! isset($roleIds[$roleKey])) continue;
            foreach ($keys as $key) {
                if (! isset($permissionIds[$key])) continue;
                DB::table('role_permission')->insertOrIgnore([
                    'role_id'=>$roleIds[$roleKey], 'permission_id'=>$permissionIds[$key],
                ]);
            }
        }
    }

    public function down(): void
    {
        $keys = ['dashboard.view','settings.view','settings.manage','support.reassign','support.escalate','support.reopen','support.view_team_metrics','support.view_worklog'];
        $permissionIds = DB::table('permissions')->whereIn('key', $keys)->pluck('id');
        if ($permissionIds->isNotEmpty()) {
            DB::table('role_permission')->whereIn('permission_id', $permissionIds)->delete();
            DB::table('user_permission_overrides')->whereIn('permission_id', $permissionIds)->delete();
        }
        DB::table('permissions')->whereIn('key', $keys)->delete();
        $roleId = DB::table('roles')->where('key', 'platform_admin')->value('id');
        if ($roleId) {
            DB::table('user_role')->where('role_id', $roleId)->delete();
            DB::table('role_permission')->where('role_id', $roleId)->delete();
            DB::table('roles')->where('id', $roleId)->delete();
        }
        Schema::dropIfExists('platform_settings');
    }
};
