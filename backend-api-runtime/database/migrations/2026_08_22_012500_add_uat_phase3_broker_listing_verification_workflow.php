<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('listing_broker_verifications', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('listing_id')->constrained('properties')->restrictOnDelete();
            $table->foreignId('geo_cell_id')->constrained('geo_cells')->restrictOnDelete();
            $table->foreignId('broker_user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('requested_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('requested_by_name_snapshot',120)->nullable();
            $table->string('broker_name_snapshot',120)->nullable();
            $table->string('status',30)->default('pending')->index();
            $table->text('request_note')->nullable();
            $table->text('response_note')->nullable();
            $table->timestampTz('requested_at')->useCurrent();
            $table->timestampTz('responded_at')->nullable();
            $table->timestampTz('cancelled_at')->nullable();
            $table->text('cancel_reason')->nullable();
            $table->timestamps();
            $table->index(['broker_user_id','status','id'],'listing_broker_verifications_broker_queue');
            $table->index(['listing_id','id'],'listing_broker_verifications_listing_history');
        });
        DB::statement("CREATE UNIQUE INDEX listing_broker_verifications_one_pending ON listing_broker_verifications (listing_id) WHERE status = 'pending'");
        if(DB::connection()->getDriverName()==='pgsql'){
            DB::statement("ALTER TABLE listing_broker_verifications ADD CONSTRAINT listing_broker_verifications_status_valid CHECK (status IN ('pending','available','unavailable','unable_to_verify','cancelled'))");
        }

        $now=now();
        if(!DB::table('permissions')->where('key','listings.verify_local')->exists()){
            DB::table('permissions')->insert([
                'key'=>'listings.verify_local','name_ar'=>'التحقق المحلي من حالة العقار','name_en'=>'Verify local property availability','scope'=>'listings','created_at'=>$now,'updated_at'=>$now,
            ]);
        }
        $permissionId=DB::table('permissions')->where('key','listings.verify_local')->value('id');
        $brokerRoleId=DB::table('roles')->where('key','broker')->value('id');
        if($permissionId&&$brokerRoleId){
            DB::table('role_permission')->insertOrIgnore(['role_id'=>$brokerRoleId,'permission_id'=>$permissionId]);
        }
    }

    public function down(): void
    {
        $permissionId=DB::table('permissions')->where('key','listings.verify_local')->value('id');
        if($permissionId){
            DB::table('role_permission')->where('permission_id',$permissionId)->delete();
            DB::table('user_permission_overrides')->where('permission_id',$permissionId)->delete();
            DB::table('permissions')->where('id',$permissionId)->delete();
        }
        DB::statement('DROP INDEX IF EXISTS listing_broker_verifications_one_pending');
        Schema::dropIfExists('listing_broker_verifications');
    }
};
