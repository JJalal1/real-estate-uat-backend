<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('roles')->where('key', 'super_admin')->update([
            'name_ar' => 'المدير العام',
            'name_en' => 'General Manager',
            'updated_at' => now(),
        ]);

        DB::table('roles')->where('key', 'content_moderator')->update([
            'name_ar' => 'مشرف المحتوى',
            'name_en' => 'Content Moderator',
            'updated_at' => now(),
        ]);

        DB::table('roles')->where('key', 'registered_user')->update([
            'name_ar' => 'مستخدم عادي',
            'name_en' => 'Regular User',
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        DB::table('roles')->where('key', 'super_admin')->update([
            'name_ar' => 'مالك التطبيق',
            'name_en' => 'Super Admin',
            'updated_at' => now(),
        ]);

        DB::table('roles')->where('key', 'content_moderator')->update([
            'name_ar' => 'مراقب المحتوى',
            'name_en' => 'Content Moderator',
            'updated_at' => now(),
        ]);

        DB::table('roles')->where('key', 'registered_user')->update([
            'name_ar' => 'مستخدم مسجل',
            'name_en' => 'Registered User',
            'updated_at' => now(),
        ]);
    }
};
