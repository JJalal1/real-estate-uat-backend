<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('viewing_bookings', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 24)->unique();
            $table->unsignedBigInteger('requester_user_id')->index();
            $table->string('requester_name_snapshot', 120);
            $table->unsignedBigInteger('host_user_id')->nullable()->index();
            $table->string('host_name_snapshot', 120)->nullable();
            $table->string('target_type', 32)->index();
            $table->unsignedBigInteger('target_id')->index();
            $table->string('target_title_snapshot', 220);
            $table->string('target_address_snapshot', 500)->nullable();
            $table->timestampTz('starts_at')->index();
            $table->timestampTz('ends_at')->index();
            $table->string('timezone', 64)->default('UTC');
            $table->string('status', 32)->default('requested')->index();
            $table->text('requester_note')->nullable();
            $table->text('host_note')->nullable();
            $table->text('cancellation_reason')->nullable();
            $table->unsignedBigInteger('last_action_by_user_id')->nullable()->index();
            $table->string('last_action_by_name_snapshot', 120)->nullable();
            $table->timestampTz('confirmed_at')->nullable();
            $table->timestampTz('declined_at')->nullable();
            $table->timestampTz('cancelled_at')->nullable();
            $table->timestampTz('completed_at')->nullable();
            $table->timestamps();
            $table->index(['requester_user_id','status','starts_at'], 'viewing_bookings_requester_status_idx');
            $table->index(['host_user_id','status','starts_at'], 'viewing_bookings_host_status_idx');
            $table->index(['target_type','target_id','status','starts_at'], 'viewing_bookings_target_status_idx');
        });

        Schema::create('viewing_booking_events', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('viewing_booking_id')->index();
            $table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot', 120)->nullable();
            $table->string('event', 80)->index();
            $table->string('from_status', 32)->nullable();
            $table->string('to_status', 32)->nullable();
            $table->json('metadata')->nullable();
            $table->timestampTz('created_at')->useCurrent()->index();
        });

        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::statement("ALTER TABLE viewing_bookings ADD CONSTRAINT viewing_bookings_target_type_check CHECK (target_type IN ('property','development_unit'))");
            DB::statement("ALTER TABLE viewing_bookings ADD CONSTRAINT viewing_bookings_status_check CHECK (status IN ('requested','confirmed','declined','cancelled','completed'))");
            DB::statement('ALTER TABLE viewing_bookings ADD CONSTRAINT viewing_bookings_time_order_check CHECK (ends_at > starts_at)');
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage13_booking_history_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'stage13 viewing booking history is immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER viewing_booking_events_immutable_update BEFORE UPDATE ON viewing_booking_events FOR EACH ROW EXECUTE FUNCTION prevent_stage13_booking_history_mutation();
CREATE TRIGGER viewing_booking_events_immutable_delete BEFORE DELETE ON viewing_booking_events FOR EACH ROW EXECUTE FUNCTION prevent_stage13_booking_history_mutation();
SQL);
        }elseif($driver==='sqlite'){
            DB::unprepared("CREATE TRIGGER viewing_booking_events_immutable_update BEFORE UPDATE ON viewing_booking_events BEGIN SELECT RAISE(ABORT, 'stage13 viewing booking history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER viewing_booking_events_immutable_delete BEFORE DELETE ON viewing_booking_events BEGIN SELECT RAISE(ABORT, 'stage13 viewing booking history is immutable'); END;");
        }

        $now=now();
        DB::table('permissions')->updateOrInsert(
            ['key'=>'bookings.manage'],
            ['name_ar'=>'إدارة طلبات المعاينة والحجوزات','name_en'=>'Manage viewing bookings','scope'=>'bookings','created_at'=>$now,'updated_at'=>$now]
        );
        $permissionId=DB::table('permissions')->where('key','bookings.manage')->value('id');
        $supportManagerId=DB::table('roles')->where('key','support_manager')->value('id');
        if($permissionId && $supportManagerId){
            DB::table('role_permission')->insertOrIgnore(['role_id'=>$supportManagerId,'permission_id'=>$permissionId]);
        }
    }

    public function down(): void
    {
        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::unprepared('DROP TRIGGER IF EXISTS viewing_booking_events_immutable_update ON viewing_booking_events');
            DB::unprepared('DROP TRIGGER IF EXISTS viewing_booking_events_immutable_delete ON viewing_booking_events');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage13_booking_history_mutation()');
        }elseif($driver==='sqlite'){
            DB::unprepared('DROP TRIGGER IF EXISTS viewing_booking_events_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS viewing_booking_events_immutable_delete');
        }
        $permissionId=DB::table('permissions')->where('key','bookings.manage')->value('id');
        if($permissionId) DB::table('role_permission')->where('permission_id',$permissionId)->delete();
        DB::table('permissions')->where('key','bookings.manage')->delete();
        Schema::dropIfExists('viewing_booking_events');
        Schema::dropIfExists('viewing_bookings');
    }
};
