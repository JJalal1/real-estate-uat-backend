<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('roles', function (Blueprint $table): void {
            $table->id();
            $table->string('key', 80)->unique();
            $table->string('name_ar', 120);
            $table->string('name_en', 120);
            $table->boolean('is_system')->default(true);
            $table->timestamps();
        });

        Schema::create('permissions', function (Blueprint $table): void {
            $table->id();
            $table->string('key', 120)->unique();
            $table->string('name_ar', 160);
            $table->string('name_en', 160);
            $table->string('scope', 80)->default('general')->index();
            $table->timestamps();
        });

        Schema::create('role_permission', function (Blueprint $table): void {
            $table->foreignId('role_id')->constrained('roles')->cascadeOnDelete();
            $table->foreignId('permission_id')->constrained('permissions')->cascadeOnDelete();
            $table->primary(['role_id', 'permission_id']);
        });

        Schema::create('user_role', function (Blueprint $table): void {
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('role_id')->constrained('roles')->cascadeOnDelete();
            $table->foreignId('assigned_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();
            $table->primary(['user_id', 'role_id']);
        });

        Schema::create('user_permission_overrides', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('permission_id')->constrained('permissions')->cascadeOnDelete();
            $table->string('effect', 10);
            $table->foreignId('assigned_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reason', 500)->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'permission_id']);
        });

        $now = now();
        $roles = [
            ['key'=>'super_admin','name_ar'=>'مالك التطبيق','name_en'=>'Super Admin'],
            ['key'=>'permissions_manager','name_ar'=>'مدير الصلاحيات','name_en'=>'Permissions Manager'],
            ['key'=>'support_manager','name_ar'=>'مدير الدعم','name_en'=>'Support Manager'],
            ['key'=>'support_agent','name_ar'=>'موظف الدعم','name_en'=>'Support Agent'],
            ['key'=>'regions_manager','name_ar'=>'مدير المناطق','name_en'=>'Regions Manager'],
            ['key'=>'content_moderator','name_ar'=>'مراقب المحتوى','name_en'=>'Content Moderator'],
            ['key'=>'broker','name_ar'=>'دلال','name_en'=>'Broker'],
            ['key'=>'registered_user','name_ar'=>'مستخدم مسجل','name_en'=>'Registered User'],
        ];
        foreach ($roles as $role) DB::table('roles')->insert($role + ['is_system'=>true,'created_at'=>$now,'updated_at'=>$now]);

        $permissions = [
            ['key'=>'users.view','name_ar'=>'عرض المستخدمين','name_en'=>'View users','scope'=>'users'],
            ['key'=>'users.manage_status','name_ar'=>'إدارة حالة الحسابات','name_en'=>'Manage account status','scope'=>'users'],
            ['key'=>'users.manage_roles','name_ar'=>'إدارة الأدوار','name_en'=>'Manage roles','scope'=>'users'],
            ['key'=>'users.manage_permissions','name_ar'=>'إدارة الصلاحيات المباشرة','name_en'=>'Manage direct permissions','scope'=>'users'],
            ['key'=>'audit.view','name_ar'=>'عرض سجل النشاط','name_en'=>'View audit log','scope'=>'audit'],
            ['key'=>'support.manage','name_ar'=>'إدارة الدعم','name_en'=>'Manage support','scope'=>'support'],
            ['key'=>'support.handle_reports','name_ar'=>'معالجة البلاغات','name_en'=>'Handle reports','scope'=>'support'],
            ['key'=>'content.moderate','name_ar'=>'مراقبة المحتوى','name_en'=>'Moderate content','scope'=>'content'],
            ['key'=>'listings.moderate','name_ar'=>'مراجعة الإعلانات','name_en'=>'Moderate listings','scope'=>'listings'],
            ['key'=>'regions.manage','name_ar'=>'إدارة المناطق','name_en'=>'Manage regions','scope'=>'regions'],
            ['key'=>'brokers.manage','name_ar'=>'إدارة الدلالين','name_en'=>'Manage brokers','scope'=>'brokers'],
            ['key'=>'conversations.review_private','name_ar'=>'فتح محادثة خاصة ضمن إجراء مصرح','name_en'=>'Review private conversation under authorized workflow','scope'=>'privacy'],
        ];
        foreach ($permissions as $permission) DB::table('permissions')->insert($permission + ['created_at'=>$now,'updated_at'=>$now]);

        $map = [
            'permissions_manager'=>['users.view','users.manage_status','users.manage_roles','users.manage_permissions','audit.view','regions.manage','brokers.manage'],
            'support_manager'=>['users.view','users.manage_status','audit.view','support.manage','support.handle_reports','listings.moderate','content.moderate','conversations.review_private'],
            'support_agent'=>['users.view','support.handle_reports','listings.moderate'],
            'regions_manager'=>['users.view','regions.manage','brokers.manage','audit.view'],
            'content_moderator'=>['users.view','content.moderate','listings.moderate'],
        ];
        $roleIds = DB::table('roles')->pluck('id','key');
        $permissionIds = DB::table('permissions')->pluck('id','key');
        foreach ($map as $roleKey => $permissionKeys) {
            foreach ($permissionKeys as $permissionKey) {
                DB::table('role_permission')->insert([
                    'role_id'=>$roleIds[$roleKey],
                    'permission_id'=>$permissionIds[$permissionKey],
                ]);
            }
        }

        // Existing real Stage 6 accounts start as Registered User. The Stage 5
        // placeholder account is intentionally excluded.
        $registeredRoleId = $roleIds['registered_user'];
        $userIds = DB::table('users')->where('email','<>','stage5-owner@local.invalid')->pluck('id');
        foreach ($userIds as $userId) {
            DB::table('user_role')->insertOrIgnore([
                'user_id'=>$userId,'role_id'=>$registeredRoleId,'assigned_by_user_id'=>null,'created_at'=>$now,
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('user_permission_overrides');
        Schema::dropIfExists('user_role');
        Schema::dropIfExists('role_permission');
        Schema::dropIfExists('permissions');
        Schema::dropIfExists('roles');
    }
};
