<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('service_offerings', function (Blueprint $table): void {
            $table->id();
            $table->string('code', 64)->unique();
            $table->string('name_ar', 160);
            $table->string('name_en', 160);
            $table->text('description_ar')->nullable();
            $table->text('description_en')->nullable();
            $table->string('target_type', 24)->index();
            $table->unsignedSmallInteger('duration_days')->nullable();
            $table->decimal('price_amount', 18, 2)->default(0);
            $table->char('currency', 3)->default('YER');
            $table->boolean('is_active')->default(false)->index();
            $table->integer('sort_order')->default(0);
            $table->unsignedBigInteger('created_by_user_id')->nullable()->index();
            $table->string('created_by_name_snapshot', 120)->nullable();
            $table->timestamps();
        });

        Schema::create('service_orders', function (Blueprint $table): void {
            $table->id();
            $table->string('reference', 24)->unique();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('user_name_snapshot', 120);
            $table->unsignedBigInteger('service_offering_id')->index();
            $table->string('service_code_snapshot', 64)->index();
            $table->string('service_name_snapshot', 160);
            $table->string('target_type', 24)->index();
            $table->unsignedBigInteger('target_id')->nullable()->index();
            $table->string('target_title_snapshot', 220)->nullable();
            $table->unsignedSmallInteger('duration_days_snapshot')->nullable();
            $table->decimal('amount', 18, 2);
            $table->char('currency', 3);
            $table->string('status', 24)->default('pending')->index();
            $table->string('payment_provider', 40)->nullable();
            $table->string('payment_reference', 120)->nullable();
            $table->timestampTz('paid_at')->nullable();
            $table->timestampTz('cancelled_at')->nullable();
            $table->timestampTz('refunded_at')->nullable();
            $table->timestamps();
            $table->unique(['payment_provider','payment_reference'], 'service_orders_provider_reference_unique');
            $table->index(['user_id','status','created_at'], 'service_orders_user_status_idx');
        });

        Schema::create('service_entitlements', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('service_order_id')->unique();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('service_code', 64)->index();
            $table->string('service_name_snapshot', 160);
            $table->string('target_type', 24)->index();
            $table->unsignedBigInteger('target_id')->nullable()->index();
            $table->string('target_title_snapshot', 220)->nullable();
            $table->timestampTz('starts_at');
            $table->timestampTz('ends_at')->nullable()->index();
            $table->string('status', 24)->default('active')->index();
            $table->timestampTz('granted_at');
            $table->timestampTz('revoked_at')->nullable();
            $table->timestamps();
            $table->index(['user_id','status','ends_at'], 'service_entitlements_user_active_idx');
        });

        Schema::create('payment_events', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('service_order_id')->index();
            $table->unsignedBigInteger('actor_user_id')->nullable()->index();
            $table->string('actor_name_snapshot', 120)->nullable();
            $table->string('event', 80)->index();
            $table->string('provider', 40)->nullable();
            $table->string('provider_reference', 120)->nullable();
            $table->decimal('amount', 18, 2)->nullable();
            $table->char('currency', 3)->nullable();
            $table->json('metadata')->nullable();
            $table->timestampTz('created_at')->useCurrent()->index();
        });

        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::statement("ALTER TABLE service_offerings ADD CONSTRAINT service_offerings_target_type_check CHECK (target_type IN ('account','property'))");
            DB::statement('ALTER TABLE service_offerings ADD CONSTRAINT service_offerings_price_check CHECK (price_amount >= 0)');
            DB::statement("ALTER TABLE service_orders ADD CONSTRAINT service_orders_target_type_check CHECK (target_type IN ('account','property'))");
            DB::statement("ALTER TABLE service_orders ADD CONSTRAINT service_orders_status_check CHECK (status IN ('pending','paid','cancelled','refunded'))");
            DB::statement('ALTER TABLE service_orders ADD CONSTRAINT service_orders_amount_check CHECK (amount >= 0)');
            DB::statement("ALTER TABLE service_entitlements ADD CONSTRAINT service_entitlements_target_type_check CHECK (target_type IN ('account','property'))");
            DB::statement("ALTER TABLE service_entitlements ADD CONSTRAINT service_entitlements_status_check CHECK (status IN ('active','revoked'))");
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage14_payment_history_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'stage14 payment event history is immutable';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER payment_events_immutable_update BEFORE UPDATE ON payment_events FOR EACH ROW EXECUTE FUNCTION prevent_stage14_payment_history_mutation();
CREATE TRIGGER payment_events_immutable_delete BEFORE DELETE ON payment_events FOR EACH ROW EXECUTE FUNCTION prevent_stage14_payment_history_mutation();
SQL);
        }elseif($driver==='sqlite'){
            DB::unprepared("CREATE TRIGGER payment_events_immutable_update BEFORE UPDATE ON payment_events BEGIN SELECT RAISE(ABORT, 'stage14 payment event history is immutable'); END;");
            DB::unprepared("CREATE TRIGGER payment_events_immutable_delete BEFORE DELETE ON payment_events BEGIN SELECT RAISE(ABORT, 'stage14 payment event history is immutable'); END;");
        }

        $now=now();
        foreach([
            ['key'=>'services.manage','name_ar'=>'إدارة الخدمات والترقيات','name_en'=>'Manage services and upgrades','scope'=>'services'],
            ['key'=>'payments.manage','name_ar'=>'إدارة تسويات واستردادات المدفوعات','name_en'=>'Manage payment settlements and refunds','scope'=>'payments'],
        ] as $permission){
            DB::table('permissions')->updateOrInsert(['key'=>$permission['key']],$permission+['created_at'=>$now,'updated_at'=>$now]);
        }
        $servicesPermission=DB::table('permissions')->where('key','services.manage')->value('id');
        $paymentsPermission=DB::table('permissions')->where('key','payments.manage')->value('id');
        $supportManager=DB::table('roles')->where('key','support_manager')->value('id');
        $superAdmin=DB::table('roles')->where('key','super_admin')->value('id');
        if($servicesPermission && $supportManager) DB::table('role_permission')->insertOrIgnore(['role_id'=>$supportManager,'permission_id'=>$servicesPermission]);
        if($servicesPermission && $superAdmin) DB::table('role_permission')->insertOrIgnore(['role_id'=>$superAdmin,'permission_id'=>$servicesPermission]);
        if($paymentsPermission && $superAdmin) DB::table('role_permission')->insertOrIgnore(['role_id'=>$superAdmin,'permission_id'=>$paymentsPermission]);

        foreach([
            ['code'=>'listing_featured_7d','name_ar'=>'إبراز الإعلان لمدة 7 أيام','name_en'=>'Featured listing - 7 days','description_ar'=>'قالب ترقية لإبراز إعلان منشور. اضبط السعر ثم فعّل الخدمة.','description_en'=>'Template for a featured published listing. Configure price before activation.','target_type'=>'property','duration_days'=>7,'sort_order'=>10],
            ['code'=>'listing_featured_30d','name_ar'=>'إبراز الإعلان لمدة 30 يوماً','name_en'=>'Featured listing - 30 days','description_ar'=>'قالب ترقية لإبراز إعلان منشور لمدة أطول.','description_en'=>'Longer featured-listing upgrade template.','target_type'=>'property','duration_days'=>30,'sort_order'=>20],
            ['code'=>'account_pro_30d','name_ar'=>'ترقية الحساب لمدة 30 يوماً','name_en'=>'Account Pro - 30 days','description_ar'=>'قالب ترقية على مستوى الحساب.','description_en'=>'Account-level upgrade template.','target_type'=>'account','duration_days'=>30,'sort_order'=>30],
        ] as $template){
            DB::table('service_offerings')->insert($template+['price_amount'=>0,'currency'=>'YER','is_active'=>false,'created_at'=>$now,'updated_at'=>$now]);
        }
    }

    public function down(): void
    {
        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::unprepared('DROP TRIGGER IF EXISTS payment_events_immutable_update ON payment_events');
            DB::unprepared('DROP TRIGGER IF EXISTS payment_events_immutable_delete ON payment_events');
            DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage14_payment_history_mutation()');
        }elseif($driver==='sqlite'){
            DB::unprepared('DROP TRIGGER IF EXISTS payment_events_immutable_update');
            DB::unprepared('DROP TRIGGER IF EXISTS payment_events_immutable_delete');
        }
        $permissionIds=DB::table('permissions')->whereIn('key',['services.manage','payments.manage'])->pluck('id');
        if($permissionIds->isNotEmpty()) DB::table('role_permission')->whereIn('permission_id',$permissionIds)->delete();
        DB::table('permissions')->whereIn('key',['services.manage','payments.manage'])->delete();
        Schema::dropIfExists('payment_events');
        Schema::dropIfExists('service_entitlements');
        Schema::dropIfExists('service_orders');
        Schema::dropIfExists('service_offerings');
    }
};
