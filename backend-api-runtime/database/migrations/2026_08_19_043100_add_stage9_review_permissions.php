<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $now=now();
        if(!DB::table('permissions')->where('key','listings.manage_blocks')->exists()) DB::table('permissions')->insert(['key'=>'listings.manage_blocks','name_ar'=>'رفع وإدارة حظر نشر العقار','name_en'=>'Manage property publication blocks','scope'=>'listings','created_at'=>$now,'updated_at'=>$now]);
        $permissionId=DB::table('permissions')->where('key','listings.manage_blocks')->value('id');
        $roleId=DB::table('roles')->where('key','support_manager')->value('id');
        if($permissionId&&$roleId&&!DB::table('role_permission')->where(['role_id'=>$roleId,'permission_id'=>$permissionId])->exists()) DB::table('role_permission')->insert(['role_id'=>$roleId,'permission_id'=>$permissionId]);
    }
    public function down(): void
    {
        $permissionId=DB::table('permissions')->where('key','listings.manage_blocks')->value('id');
        if($permissionId){DB::table('role_permission')->where('permission_id',$permissionId)->delete();DB::table('user_permission_overrides')->where('permission_id',$permissionId)->delete();DB::table('permissions')->where('id',$permissionId)->delete();}
    }
};
