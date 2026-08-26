<?php
namespace Tests\Feature;

use App\Models\PaymentEvent;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\ServiceEntitlement;
use App\Models\ServiceOffering;
use App\Models\ServiceOrder;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class Stage14ServicesPaymentsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_catalog_order_ownership_and_price_snapshot_are_enforced(): void
    {
        [$customer,$customerHeaders]=$this->user('s14-customer@example.test','+967760000001');
        [, $outsiderHeaders]=$this->user('s14-outsider@example.test','+967760000002');
        [$manager,$managerHeaders]=$this->user('s14-manager@example.test','+967760000003',['support_manager']);
        $property=$this->property($customer,'Stage 14 listing A');
        $offer=$this->offer('s14_featured','property',1250,7,true);

        $this->getJson('/api/services/catalog')->assertOk()->assertJsonPath('data.0.code','s14_featured');
        $this->withHeaders($outsiderHeaders)->postJson('/api/services/orders',['offering_id'=>$offer->id,'target_id'=>$property->id])->assertNotFound();
        $order=$this->withHeaders($customerHeaders)->postJson('/api/services/orders',['offering_id'=>$offer->id,'target_id'=>$property->id])->assertCreated()->assertJsonPath('data.status','pending')->assertJsonPath('data.amount','1250.00');
        $orderId=(int)$order->json('data.id');
        $this->withHeaders($managerHeaders)->patchJson("/api/admin/services/offers/{$offer->id}",['price_amount'=>2000,'currency'=>'YER','is_active'=>true])->assertOk();
        $this->withHeaders($customerHeaders)->getJson("/api/services/orders/$orderId")->assertOk()->assertJsonPath('data.amount','1250.00');
        $this->assertSame($manager->id,(int)User::query()->findOrFail($manager->id)->id);
    }

    public function test_payment_permission_is_separate_and_settlement_activates_exactly_once(): void
    {
        [$customer,$customerHeaders]=$this->user('s14-pay-customer@example.test','+967760000004');
        [, $managerHeaders]=$this->user('s14-pay-manager@example.test','+967760000005',['support_manager']);
        [, $adminHeaders]=$this->user('s14-pay-admin@example.test','+967760000006',['super_admin']);
        $offer=$this->offer('s14_account_pro','account',500,30,true);
        $orderId=(int)$this->withHeaders($customerHeaders)->postJson('/api/services/orders',['offering_id'=>$offer->id])->assertCreated()->json('data.id');
        $payload=['provider'=>'manual_admin','provider_reference'=>'S14-TEST-PAY-001'];
        $this->withHeaders($managerHeaders)->postJson("/api/admin/payments/orders/$orderId/settle",$payload)->assertForbidden();
        $this->withHeaders($adminHeaders)->postJson("/api/admin/payments/orders/$orderId/settle",$payload)->assertOk()->assertJsonPath('data.status','paid')->assertJsonPath('data.entitlement.is_active',true);
        $this->withHeaders($adminHeaders)->postJson("/api/admin/payments/orders/$orderId/settle",$payload)->assertConflict();
        $this->assertDatabaseHas('service_entitlements',['service_order_id'=>$orderId,'status'=>'active']);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$customer->id,'type'=>'service_payment_confirmed','entity_id'=>$orderId]);
        $this->assertDatabaseHas('payment_events',['service_order_id'=>$orderId,'event'=>'payment_settled']);
    }

    public function test_pending_order_can_be_cancelled_and_cannot_then_be_settled(): void
    {
        [, $customerHeaders]=$this->user('s14-cancel@example.test','+967760000007');
        [, $adminHeaders]=$this->user('s14-cancel-admin@example.test','+967760000008',['super_admin']);
        $offer=$this->offer('s14_cancel_service','account',100,14,true);
        $orderId=(int)$this->withHeaders($customerHeaders)->postJson('/api/services/orders',['offering_id'=>$offer->id])->assertCreated()->json('data.id');
        $this->withHeaders($customerHeaders)->postJson("/api/services/orders/$orderId/cancel")->assertOk()->assertJsonPath('data.status','cancelled');
        $this->withHeaders($adminHeaders)->postJson("/api/admin/payments/orders/$orderId/settle",['provider'=>'manual_admin','provider_reference'=>'S14-CANCELLED-1'])->assertConflict();
    }

    public function test_refund_revokes_entitlement_and_payment_history_is_immutable(): void
    {
        [, $customerHeaders]=$this->user('s14-refund@example.test','+967760000009');
        [, $adminHeaders]=$this->user('s14-refund-admin@example.test','+967760000010',['super_admin']);
        $offer=$this->offer('s14_refund_service','account',750,30,true);
        $orderId=(int)$this->withHeaders($customerHeaders)->postJson('/api/services/orders',['offering_id'=>$offer->id])->json('data.id');
        $this->withHeaders($adminHeaders)->postJson("/api/admin/payments/orders/$orderId/settle",['provider'=>'bank_transfer','provider_reference'=>'S14-BANK-REF-1'])->assertOk();
        $this->withHeaders($adminHeaders)->postJson("/api/admin/payments/orders/$orderId/refund",['reason'=>'Customer requested refund'])->assertOk()->assertJsonPath('data.status','refunded')->assertJsonPath('data.entitlement.status','revoked');
        $this->assertDatabaseHas('service_entitlements',['service_order_id'=>$orderId,'status'=>'revoked']);
        $event=PaymentEvent::query()->where('service_order_id',$orderId)->firstOrFail();
        try{DB::table('payment_events')->where('id',$event->id)->update(['event'=>'tampered']);$this->fail('Immutable payment event update was allowed.');}catch(QueryException){}
        try{DB::table('payment_events')->where('id',$event->id)->delete();$this->fail('Immutable payment event delete was allowed.');}catch(QueryException){}
        $this->assertDatabaseHas('payment_events',['id'=>$event->id,'event'=>'order_created']);
    }

    public function test_permissions_templates_and_prior_stage_protections_exist_without_card_columns(): void
    {
        foreach(['service_offerings','service_orders','service_entitlements','payment_events','viewing_bookings','viewing_booking_events'] as $table)$this->assertTrue(Schema::hasTable($table));
        $this->assertDatabaseHas('permissions',['key'=>'services.manage']);$this->assertDatabaseHas('permissions',['key'=>'payments.manage']);
        $support=Role::query()->where('key','support_manager')->firstOrFail();$super=Role::query()->where('key','super_admin')->firstOrFail();
        $services=DB::table('permissions')->where('key','services.manage')->value('id');$payments=DB::table('permissions')->where('key','payments.manage')->value('id');
        $this->assertTrue(DB::table('role_permission')->where('role_id',$support->id)->where('permission_id',$services)->exists());
        $this->assertFalse(DB::table('role_permission')->where('role_id',$support->id)->where('permission_id',$payments)->exists());
        $this->assertTrue(DB::table('role_permission')->where('role_id',$super->id)->where('permission_id',$payments)->exists());
        $this->assertSame(3,ServiceOffering::query()->whereIn('code',['listing_featured_7d','listing_featured_30d','account_pro_30d'])->count());
        $this->assertSame(0,ServiceOffering::query()->whereIn('code',['listing_featured_7d','listing_featured_30d','account_pro_30d'])->where('is_active',true)->count());
        $columns=array_merge(Schema::getColumnListing('service_orders'),Schema::getColumnListing('payment_events'));
        foreach($columns as $column)$this->assertDoesNotMatchRegularExpression('/card|pan|cvv|cvc|password|secret|token/i',$column);
        $this->assertDatabaseHas('permissions',['key'=>'bookings.manage']);$this->assertDatabaseHas('permissions',['key'=>'conversations.review_private']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Stage 14 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        $sync=[];foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($sync);
        $plain='re14_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'stage14-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function property(User $owner,string $title): Property
    {
        $asset=PropertyAsset::query()->create(['created_by_user_id'=>$owner->id,'identity_hash'=>hash('sha256',$title.uniqid('',true)),'identity_version'=>1,'property_type'=>'apartment','canonical_address'=>'Stage 14 address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,'area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'status'=>'active']);
        return Property::query()->create(['user_id'=>$owner->id,'property_asset_id'=>$asset->id,'title'=>$title,'description'=>'Stage 14 published listing','purpose'=>'sale','type'=>'apartment','price'=>10000000,'currency'=>'YER','area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'address'=>'Stage 14 address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now()]);
    }

    private function offer(string $code,string $target,float $price,int $days,bool $active): ServiceOffering
    {
        return ServiceOffering::query()->create(['code'=>$code,'name_ar'=>'خدمة اختبار','name_en'=>'Test service','target_type'=>$target,'duration_days'=>$days,'price_amount'=>$price,'currency'=>'YER','is_active'=>$active,'sort_order'=>100]);
    }
}
