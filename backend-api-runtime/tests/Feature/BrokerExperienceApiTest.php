<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\AdvertiserRating;
use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use App\Models\SupportTask;
use App\Services\SupportTaskService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use App\Services\BrokerAvailabilityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class BrokerExperienceApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->startOfSecond());
    }

    public function test_availability_period_grace_pause_and_bulk_renewal_preserve_review_authority(): void
    {
        [$broker,$headers]=$this->actor('period',true);
        $sale=$this->listing($broker,'sale');
        $rent=$this->listing($broker,'rent');
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertTrue($sale->fresh()->availability_due_at->equalTo(now()->addDays(14)));
        $this->assertTrue($rent->fresh()->availability_due_at->equalTo(now()->addDays(7)));
        $this->travel(7)->days();
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertDatabaseHas('user_notifications',['user_id'=>$broker->id,'type'=>'broker_availability_due']);
        $this->assertTrue($rent->fresh()->isPubliclyAvailable());
        $this->travel(2)->days();
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertFalse($rent->fresh()->isPubliclyAvailable());
        $this->getJson('/api/properties')->assertJsonMissing(['id'=>$rent->id]);
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$sale->id,$rent->id],'state'=>'available'])
            ->assertOk()->assertJsonPath('data.updated',2);
        $this->assertTrue($rent->fresh()->isPubliclyAvailable());
        $rent->forceFill(['status'=>'draft','review_status'=>'returned_for_correction'])->saveQuietly();
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$rent->id],'state'=>'available'])->assertConflict();
        $this->assertSame('returned_for_correction',$rent->fresh()->review_status);
    }

    public function test_bulk_update_is_atomic_and_rejects_foreign_listings(): void
    {
        [$broker,$headers]=$this->actor('own',true);
        [$other]=$this->actor('other',true);
        $own=$this->listing($broker);
        $foreign=$this->listing($other);
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$own->id,$foreign->id],'state'=>'paused'])->assertForbidden();
        $this->assertSame('available',$own->fresh()->availability_status);
        $this->assertSame('available',$foreign->fresh()->availability_status);
    }

    public function test_two_party_result_unlocks_rating_and_freezes_existing_sai_without_an_agreement(): void
    {
        [$broker,$brokerHeaders]=$this->actor('confirmed',true);
        [$customer,$customerHeaders]=$this->actor('buyer');
        [, $outsiderHeaders]=$this->actor('outside');
        $property=$this->listing($broker);
        $thread=$this->conversation($customerHeaders,$property);
        $this->withHeaders($customerHeaders)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>5])->assertUnprocessable();
        $result=$this->withHeaders($brokerHeaders)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated();
        $id=(int)$result->json('data.id');
        $this->withHeaders($outsiderHeaders)->getJson('/api/broker/deals/'.$id)->assertNotFound();
        $this->withHeaders($brokerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertForbidden();
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->withHeaders($customerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk()->assertJsonPath('data.status','confirmed');
        $this->withHeaders($customerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $this->assertDatabaseCount('broker_deal_outcomes',1);
        $this->assertDatabaseCount('property_agreements',0);
        $this->assertDatabaseCount('property_platform_receivables',1);
        $due=PropertyPlatformReceivable::query()->firstOrFail();
        $this->assertSame(500.0,$due->amount_total);
        $this->assertTrue($due->due_at->equalTo(now()->addHours(24)));
        $this->assertDatabaseHas('property_deal_financial_terms',['broker_deal_outcome_id'=>$id,'property_agreement_id'=>null,'buyer_user_id'=>$customer->id]);
        $this->withHeaders($customerHeaders)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>4])->assertCreated();
        $this->getJson('/api/advertisers/'.$broker->id.'/ratings/summary')->assertJsonPath('data.count',1)->assertJsonPath('data.average',4);
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/finance')->assertOk()->assertJsonPath('data.balances.0.open',500);
        $this->withHeaders($outsiderHeaders)->getJson('/api/broker/finance')->assertForbidden();
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/customers')->assertJsonPath('data.0.stage','completed');
    }

    public function test_denied_result_is_reviewable_but_never_counts_or_unlocks_rating(): void
    {
        [$broker,$bh]=$this->actor('disputed',true);
        [$customer,$ch]=$this->actor('deny');
        $property=$this->listing($broker);
        $thread=$this->conversation($ch,$property);
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk()->assertJsonPath('data.status','disputed');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertConflict();
        $this->withHeaders($ch)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>5])->assertUnprocessable();
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->assertDatabaseHas('support_cases',['target_type'=>'broker_deal_outcome','target_id'=>$id]);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertJsonPath('data.completed_deals',0);
        $this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->assertJsonPath('data.id',$id);
        $this->assertDatabaseCount('broker_deal_outcomes',1);
    }

    public function test_directory_locality_public_privacy_and_legacy_ratings_are_not_verified_stars(): void
    {
        [$broker]=$this->actor('local',true,'صنعاء');
        [$other]=$this->actor('elsewhere',true,'عدن');
        [$rater]=$this->actor('legacy-rater');
        $this->listing($broker);$this->listing($other);
        AdvertiserRating::query()->create(['advertiser_user_id'=>$other->id,'advertiser_name_snapshot'=>$other->name,'rater_user_id'=>$rater->id,
            'rater_name_snapshot'=>$rater->name,'rating'=>5,'status'=>'visible']);
        $response=$this->getJson('/api/brokers?governorate='.urlencode('صنعاء'))->assertOk()->assertJsonPath('data.0.id',$broker->id);
        $response->assertJsonMissing(['email'=>$broker->email])->assertJsonMissing(['phone'=>$broker->phone]);
        $this->getJson('/api/advertisers/'.$other->id.'/profile')->assertJsonPath('data.rating_count',0)->assertJsonPath('data.rating_average',0);
        $this->assertDatabaseCount('advertiser_ratings',1);
    }

    public function test_views_are_explicit_and_deduplicated_and_read_notifications_leave_the_feed(): void
    {
        [$broker]=$this->actor('analytics',true);
        [, $customerHeaders]=$this->actor('reader');
        $property=$this->listing($broker);
        $this->getJson('/api/properties/'.$property->id)->assertOk();
        $this->assertSame(0,(int)$property->fresh()->view_count);
        $body=['viewer_key'=>'a-stable-test-viewer-123'];
        $this->withHeaders($customerHeaders)->postJson('/api/properties/'.$property->id.'/view',$body)->assertOk()->assertJsonPath('data.recorded',true);
        $this->withHeaders($customerHeaders)->postJson('/api/properties/'.$property->id.'/view',$body)->assertOk()->assertJsonPath('data.recorded',false);
        $this->assertSame(1,(int)$property->fresh()->view_count);
        $customerId=User::query()->where('email','reader@broker.test')->value('id');
        $notification=app(\App\Services\UserNotificationService::class)->create($customerId,'broker_test','Notification');
        $this->withHeaders($customerHeaders)->postJson('/api/notifications/'.$notification->id.'/read')->assertOk();
        $this->withHeaders($customerHeaders)->getJson('/api/notifications')->assertJsonCount(0,'data');
        $this->assertNotNull($notification->fresh()->read_at);
    }

    public function test_reminders_merge_across_batches_and_public_photo_is_separate_from_verification(): void
    {
        Storage::fake('public');
        [$broker,$bh]=$this->actor('photos',true);
        [, $outsider]=$this->actor('photos-outside');
        $a=$this->listing($broker);$b=$this->listing($broker);
        $a->forceFill(['availability_due_at'=>now()->subHour()])->saveQuietly();
        $b->forceFill(['availability_due_at'=>now()->subHour()])->saveQuietly();
        app(BrokerAvailabilityService::class)->sweep(1);
        app(BrokerAvailabilityService::class)->sweep(1);
        $notices=DB::table('user_notifications')->where('type','broker_availability_due')->get();
        $this->assertCount(1,$notices);
        $this->assertSame(2,json_decode($notices->first()->data,true)['count']);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertJsonPath('data.photo_url',null);
        $this->get('/api/advertisers/'.$broker->id.'/photo')->assertNotFound();
        $this->withHeaders($outsider)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->image('photo.jpg')])->assertForbidden();
        $this->withHeaders($bh)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->image('public-photo.jpg')])->assertOk();
        $this->get('/api/advertisers/'.$broker->id.'/photo')->assertOk();
        $data=$this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertOk()->json('data');
        $this->assertStringContainsString('/api/advertisers/'.$broker->id.'/photo?v=',$data['photo_url']);
        $this->assertArrayNotHasKey('public_professional_photo_path',$data);
        $this->assertArrayNotHasKey('documents',$data);
    }

    public function test_claimed_support_can_retry_but_cannot_artificially_confirm_a_disputed_deal(): void
    {
        [$broker,$bh]=$this->actor('retry',true);
        [, $ch]=$this->actor('retry-client');
        [$agent,$ah]=$this->actor('retry-agent');
        [, $otherHeaders]=$this->actor('retry-other-agent');
        $role=Role::query()->where('key','support_agent')->firstOrFail();
        $agent->roles()->attach($role->id,['created_at'=>now()]);
        $permissions=DB::table('permissions')->where('key','support.handle_reports')->pluck('id');
        foreach ($permissions as $permission) DB::table('role_permission')->insertOrIgnore(['role_id'=>$role->id,'permission_id'=>$permission]);
        $thread=$this->conversation($ch,$this->listing($broker));
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk();
        $outcome=BrokerDealOutcome::query()->findOrFail($id);
        $task=SupportTask::query()->where('source_type','support_ticket')->where('source_id',$outcome->support_case_id)->firstOrFail();
        $url='/api/broker/support/tasks/'.$task->id.'/resolution';
        $this->withHeaders($otherHeaders)->postJson($url,['decision'=>'retry','note'=>'review request'])->assertForbidden();
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'review request'])->assertConflict();
        $this->withHeaders($ah)->postJson('/api/admin/workspace/tasks/'.$task->id.'/claim',[])->assertOk();
        $this->withHeaders($ah)->postJson($url,['decision'=>'confirmed','note'=>'review request'])->assertUnprocessable();
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'العميل يحتاج إعادة تأكيد النتيجة'])->assertOk()->assertJsonPath('data.status','pending_customer');
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk();
        $this->assertDatabaseCount('support_cases',1);
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'أعيد طلب تأكيد النتيجة بعد مراجعة الطرفين'])->assertOk();
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $this->assertDatabaseCount('property_platform_receivables',1);
        $this->assertDatabaseHas('support_cases',['id'=>$outcome->support_case_id,'status'=>'resolved']);
    }

    public function test_receivable_payment_works_without_an_agreement_and_legacy_creation_is_dormant(): void
    {
        [$broker,$bh]=$this->actor('standalone-finance',true);
        [, $ch]=$this->actor('standalone-buyer');
        [, $oh]=$this->actor('standalone-outsider');
        $thread=$this->conversation($ch,$this->listing($broker));
        $this->withHeaders($ch)->postJson('/api/messages/threads/'.$thread.'/agreement',[])->assertStatus(410);
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $due=PropertyPlatformReceivable::query()->firstOrFail();
        $this->withHeaders($oh)->getJson('/api/finance/receivables/'.$due->id)->assertForbidden();
        $this->withHeaders($bh)->getJson('/api/finance/receivables/'.$due->id)->assertOk()->assertJsonPath('data.agreement_id',null)->assertJsonPath('data.can_pay_full',false);
        $method=\App\Models\PropertyPaymentMethod::query()->create(['key'=>'broker-test-bank','name_ar'=>'وسيلة الاختبار','asset_key'=>'bank',
            'beneficiary_name'=>'اختبار','destination_label'=>'الحساب','destination_value'=>'TEST-ACCOUNT','currency'=>'YER',
            'min_amount'=>0,'max_amount'=>9999999,'allows_full_payment'=>false,'allows_sai_only'=>true,'is_enabled'=>true,'sort_order'=>100]);
        $this->withHeaders($bh)->postJson('/api/finance/receivables/'.$due->id.'/payments',['payment_method_id'=>$method->id])->assertCreated()->assertJsonPath('data.amount',500);
        $this->assertDatabaseCount('property_agreements',0);
    }

    private function actor(string $key, bool $professional=false, string $governorate='صنعاء'): array
    {
        $user=User::query()->create(['name'=>'Broker Test '.$key,'email'=>$key.'@broker.test','phone'=>'+9677'.substr(hash('crc32b',$key),0,8),
            'phone_verified_at'=>now(),'profile_completed_at'=>now(),'account_status'=>'active','password'=>Hash::make('broker-test-password')]);
        $role=Role::query()->where('key','registered_user')->firstOrFail();
        $user->roles()->attach($role->id,['assigned_by_user_id'=>null,'created_at'=>now()]);
        if ($professional) AccountVerificationProfile::query()->create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','reviewed_at'=>now(),
            'details'=>['governorate'=>$governorate,'work_areas'=>[$governorate]]]);
        $token='broker_'.hash('sha256',$key);
        $user->apiTokens()->create(['name'=>'broker-test','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addYear()]);
        return [$user,['Authorization'=>'Bearer '.$token,'Accept'=>'application/json']];
    }

    private function listing(User $broker, string $purpose='sale'): Property
    {
        $p=Property::query()->create(['user_id'=>$broker->id,'title'=>'Broker listing '.$purpose,'purpose'=>$purpose,'type'=>'apartment',
            'price'=>100000,'monthly_rent'=>$purpose==='rent' ? 100000 : null,'currency'=>'YER','latitude'=>15.35,'longitude'=>44.2,
            'status'=>'published','review_status'=>'approved','published_at'=>now()]);
        $sai=PropertySaiTerm::query()->create(['property_id'=>$p->id,'version'=>1,'advertiser_type'=>'broker','purpose'=>$purpose,
            'source_mode'=>'broker_requested','requested_broker_rate_percent'=>2,'sai_rate_percent'=>2,'payer'=>'advertiser',
            'calculation_basis'=>$purpose==='rent' ? 'monthly_rent' : 'sale_price','platform_share_percent'=>25,'broker_share_percent'=>75,
            'platform_terms_status'=>'accepted','platform_terms_accepted_at'=>now(),'created_by_user_id'=>$broker->id]);
        $p->forceFill(['current_sai_term_id'=>$sai->id])->saveQuietly();
        return $p;
    }

    private function conversation(array $headers, Property $property): int
    {
        return (int)$this->withHeaders($headers)->postJson('/api/properties/'.$property->id.'/conversation',[])->assertCreated()->json('data.id');
    }
}
