<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\PropertyFinancialService;
use App\Services\UserNotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Wave4ListingJourneyTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
        $this->travelTo(now()->startOfSecond());
    }

    public function test_rental_apartment_moves_from_draft_to_review_publication_consent_and_two_party_settlement(): void
    {
        [$broker,$headers]=$this->actor('journey','broker');
        [$support,$supportHeaders]=$this->actor('reviewer',null,['support_agent']);
        [$customer,$customerHeaders]=$this->actor('customer');
        [, $outsiderHeaders]=$this->actor('outside');
        $created=$this->withHeaders($headers)->post('/api/properties',$this->payload(['images'=>[]]))->assertCreated()
            ->assertJsonPath('data.area_value',null)->assertJsonPath('data.rental_conditions',[])
            ->assertJsonPath('data.price',100000)->assertJsonPath('data.monthly_rent',100000);
        $id=(int)$created->json('data.id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",['broker_sai_rate_percent'=>50,'defer_platform_terms'=>true])
            ->assertOk()->assertJsonPath('data.sai_management.platform_terms_status','pending');
        $term=PropertySaiTerm::query()->findOrFail(Property::findOrFail($id)->current_sai_term_id);
        $frozen=$term->getRawOriginal();
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true])->assertConflict();
        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")->assertConflict();
        $this->assertDatabaseCount('property_sai_attestations',0);
        $this->withHeaders(['Authorization'=>''])->getJson("/api/properties/$id")->assertNotFound();
        // Partial updates retain monthly rent and do not require hidden lease/advance fields.
        $this->withHeaders($headers)->post("/api/properties/$id",['images'=>[UploadedFile::fake()->image('real-property.jpg')]])->assertOk();
        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")->assertOk()->assertJsonPath('data.review_status','submitted');
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$id/approve",['reason'=>'Reviewed submitted property facts and photos.'])->assertOk()->assertJsonPath('data.status','published');
        $this->withHeaders(['Authorization'=>''])->getJson("/api/properties/$id")->assertOk()
            ->assertJsonPath('data.display_price',100000)->assertJsonPath('data.price_display_note','السعي 50%')
            ->assertJsonPath('data.sai.rate_percent',50)->assertJsonMissingPath('data.sai.platform_share_percent')
            ->assertJsonPath('data.rental_term_months',null)->assertJsonPath('data.advance_months',null);
        $thread=(int)$this->withHeaders($customerHeaders)->postJson("/api/properties/$id/conversation")->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal",[])->assertConflict();
        $this->assertDatabaseCount('broker_deal_outcomes',0);
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->withHeaders($outsiderHeaders)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true])->assertForbidden();
        $text=app(PropertyFinancialService::class)->attestationText(Property::findOrFail($id));
        $this->assertStringContainsString('20%',$text);
        $this->assertStringContainsString('عميل عبر المنصة',$text);
        $this->withHeaders($headers)->getJson('/api/finance/sai-attestations/pending')->assertOk()->assertJsonFragment(['property_id'=>$id,'text'=>$text]);
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true])->assertOk();
        $receipt=(array)DB::table('property_sai_attestations')->where('sai_term_id',$term->id)->first();
        $this->travel(1)->minutes();
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true])->assertOk();
        $this->assertSame($receipt,(array)DB::table('property_sai_attestations')->where('sai_term_id',$term->id)->first());
        $this->assertSame($frozen,$term->fresh()->getRawOriginal());
        $deal=(int)$this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal",[])->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/broker/deals/$deal/decision",['confirmed'=>true])->assertForbidden();
        $this->withHeaders($customerHeaders)->postJson("/api/broker/deals/$deal/decision",['confirmed'=>true])->assertOk()->assertJsonPath('data.status','confirmed');
        $this->withHeaders($customerHeaders)->postJson("/api/broker/deals/$deal/decision",['confirmed'=>true])->assertOk();
        $this->assertDatabaseCount('property_deal_financial_terms',1);
        $this->assertDatabaseCount('property_platform_receivables',1);
        $this->assertDatabaseHas('property_deal_financial_terms',['broker_deal_outcome_id'=>$deal,
            'buyer_user_id'=>$customer->id,'base_amount'=>100000,'monthly_basis_amount'=>100000,'sai_total_amount'=>50000,'platform_share_amount'=>10000,'advertiser_sai_share_amount'=>40000]);
        $snapshot=json_decode(DB::table('property_deal_financial_terms')->where('broker_deal_outcome_id',$deal)->value('snapshot'),true);
        $this->assertSame($term->id,$snapshot['sai_term_id']);
        $this->assertDatabaseHas('property_platform_receivables',['advertiser_user_id'=>$broker->id,'amount_total'=>10000]);
        $this->assertSame($frozen,$term->fresh()->getRawOriginal());
    }

    public function test_old_customer_can_complete_under_frozen_pending_terms_after_the_listing_rate_changes(): void
    {
        [$broker,$headers]=$this->actor('frozen-rate','broker');
        [$customer,$customerHeaders]=$this->actor('frozen-customer');
        [, $outsiderHeaders]=$this->actor('frozen-outsider');
        $id=(int)$this->withHeaders($headers)->post('/api/properties',$this->payload())->assertCreated()->json('data.id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",['broker_sai_rate_percent'=>50,'defer_platform_terms'=>true])->assertOk();
        Property::findOrFail($id)->forceFill(['status'=>'published','review_status'=>'approved','published_at'=>now()])->save();
        $old=PropertySaiTerm::findOrFail(Property::findOrFail($id)->current_sai_term_id);
        $oldRaw=$old->getRawOriginal();
        $thread=(int)$this->withHeaders($customerHeaders)->postJson("/api/properties/$id/conversation")->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/properties/$id",['monthly_rent'=>120000])->assertOk();
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",['broker_sai_rate_percent'=>60,'defer_platform_terms'=>true])->assertOk();
        Property::findOrFail($id)->forceFill(['status'=>'published','review_status'=>'approved','published_at'=>now()])->save();
        $current=PropertySaiTerm::findOrFail(Property::findOrFail($id)->current_sai_term_id);
        $this->assertNotSame($old->id,$current->id);
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true])->assertOk();
        $challenge=$this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal",['basis_amount'=>110000])
            ->assertConflict()->assertJsonPath('code','sai_consent_required')->assertJsonPath('data.sai_term_id',$old->id);
        $this->assertStringContainsString('50%',$challenge->json('data.text'));
        $this->assertStringNotContainsString('60%',$challenge->json('data.text'));
        $this->assertDatabaseCount('broker_deal_outcomes',0);
        $this->assertDatabaseHas('properties',['id'=>$id,'availability_status'=>'available']);
        $this->withHeaders($outsiderHeaders)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true,'sai_term_id'=>$old->id])->assertForbidden();
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation",['accepted'=>true,'sai_term_id'=>$old->id])->assertOk();
        $this->assertDatabaseHas('property_sai_attestations',['sai_term_id'=>$old->id,'user_id'=>$broker->id,'text_snapshot'=>$challenge->json('data.text')]);
        $this->assertSame($oldRaw,$old->fresh()->getRawOriginal());
        $deal=(int)$this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal",['basis_amount'=>110000])->assertCreated()->json('data.id');
        $this->withHeaders($customerHeaders)->postJson("/api/broker/deals/$deal/decision",['confirmed'=>true])->assertOk();
        $this->assertDatabaseHas('property_deal_financial_terms',['broker_deal_outcome_id'=>$deal,'sai_total_amount'=>55000,
            'platform_share_amount'=>11000,'advertiser_sai_share_amount'=>44000]);
        $this->assertDatabaseHas('message_threads',['id'=>$thread,'sai_term_id'=>$old->id]);
        $this->assertDatabaseHas('properties',['id'=>$id,'current_sai_term_id'=>$current->id]);
        $this->assertSame($oldRaw,$old->fresh()->getRawOriginal());
    }

    public function test_sale_apartment_requires_area_and_floor_and_cannot_create_new_whole_floor_identity(): void
    {
        [, $headers]=$this->actor('sale','broker');
        $base=['purpose'=>'sale','tenure_type'=>'freehold','price'=>50000000,'monthly_rent'=>null];
        $this->withHeaders($headers)->post('/api/properties',$this->payload($base))->assertUnprocessable()->assertJsonValidationErrors('area_value');
        $this->withHeaders($headers)->post('/api/properties',$this->payload($base+['area_value'=>140,'area_unit'=>'sqm','floor_number'=>'']))->assertUnprocessable()->assertJsonValidationErrors('floor_number');
        foreach ([['unit_occupies_entire_floor'=>1],['type'=>'floor']] as $scope) {
            $this->withHeaders($headers)->post('/api/properties',$this->payload(array_merge($base,['area_value'=>140,'area_unit'=>'sqm'],$scope)))
                ->assertUnprocessable()->assertJsonValidationErrors('unit_occupies_entire_floor');
        }
        $this->assertDatabaseCount('properties',0);
    }

    public function test_only_selected_rental_conditions_are_stored_edited_and_removed_without_hidden_lease_fields(): void
    {
        [, $headers]=$this->actor('conditions','broker');
        $conditions=[['kind'=>'advance','months'=>2],['kind'=>'guarantor'],['kind'=>'special','text'=>'لا يسمح بالتأجير من الباطن']];
        $id=(int)$this->withHeaders($headers)->post('/api/properties',$this->payload(['rental_conditions'=>json_encode($conditions,JSON_UNESCAPED_UNICODE),
            'price_display_mode'=>'includes_sai','rental_term_months'=>24,'advance_months'=>20]))->assertCreated()->json('data.id');
        $property=Property::findOrFail($id);
        $this->assertSame($conditions,$property->rental_conditions);
        $this->assertSame(2,$property->advance_months);
        $this->assertNull($property->rental_term_months);
        $this->assertSame('excludes_sai',$property->price_display_mode);
        $this->assertSame(100000.0,(float)$property->price);
        $this->withHeaders($headers)->postJson("/api/properties/$id",['rental_conditions'=>[['kind'=>'advance','months'=>8],['kind'=>'duration','months'=>3]]])->assertUnprocessable();
        $this->assertSame($conditions,$property->fresh()->rental_conditions);
        $this->withHeaders($headers)->postJson("/api/properties/$id",['rental_conditions'=>[]])->assertOk()->assertJsonPath('data.rental_conditions',[]);
        $this->assertNull($property->fresh()->advance_months);
        $this->assertNull($property->fresh()->rental_term_months);
        $this->withHeaders($headers)->postJson("/api/properties/$id",['purpose'=>'sale','tenure_type'=>'freehold','area_value'=>140,'area_unit'=>'sqm','rental_conditions'=>$conditions])->assertUnprocessable();
        foreach ([[['kind'=>'deposit','amount'=>3000]],[['kind'=>'special','text'=>'']],[['kind'=>'guarantor'],['kind'=>'guarantor']]] as $bad) {
            $this->withHeaders($headers)->postJson("/api/properties/$id",['rental_conditions'=>$bad])->assertUnprocessable();
        }
    }

    public function test_legacy_viewing_notifications_are_hidden_but_preserved_and_cannot_be_generated_again(): void
    {
        [$user,$headers]=$this->actor('notifications');
        foreach (UserNotification::RETIRED_VIEWING_TYPES as $type) {
            DB::table('user_notifications')->insert(['user_id'=>$user->id,'type'=>$type,'title'=>'Legacy visit','entity_type'=>'message_thread','entity_id'=>1,'created_at'=>now()]);
            $this->assertNull(app(UserNotificationService::class)->create($user->id,$type,'Retired visit'));
        }
        $visible=app(UserNotificationService::class)->create($user->id,'account_verification_approved','تم اعتماد الحساب');
        $this->withHeaders($headers)->getJson('/api/notifications')->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.id',$visible->id);
        $this->withHeaders($headers)->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count',1);
        $this->withHeaders($headers)->postJson('/api/notifications/read-all')->assertOk()->assertJsonPath('data.updated',1);
        $this->assertSame(count(UserNotification::RETIRED_VIEWING_TYPES),DB::table('user_notifications')->whereNull('read_at')->count());
        $this->assertDatabaseCount('user_notifications',count(UserNotification::RETIRED_VIEWING_TYPES)+1);
    }

    private function actor(string $key, ?string $type=null, array $roles=[]): array
    {
        $user=User::create(['name'=>'أحمد محمد علي صالح','email'=>$key.'@wave4.example.test','phone'=>'+96777'.substr(hash('sha256',$key),0,10),
            'password'=>Hash::make('fixture-'.$key),'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $sync=[]; foreach (array_merge(['registered_user'],$roles) as $role) $sync[Role::where('key',$role)->firstOrFail()->id]=['created_at'=>now()];
        $user->roles()->sync($sync);
        if ($type) AccountVerificationProfile::create(['user_id'=>$user->id,'type'=>$type,'status'=>'approved','submitted_at'=>now()->subDay(),'reviewed_at'=>now()]);
        $token='wave4_'.hash('sha256',$key);
        $user->apiTokens()->create(['name'=>'wave4-test','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addHour()]);
        return [$user->fresh(),['Authorization'=>'Bearer '.$token,'Accept'=>'application/json']];
    }

    private function payload(array $changes=[]): array
    {
        return array_merge(['listing_input_version'=>6,'title'=>'شقة إيجار في حدة','description'=>'ثلاث غرف في الدور الثاني.','purpose'=>'rent','type'=>'apartment',
            'price'=>100000,'monthly_rent'=>100000,'currency'=>'YER','area_value'=>null,'area_unit'=>null,'bedrooms'=>3,'bathrooms'=>2,
            'floor_number'=>'2','unit_number'=>'الشمالية','has_parking'=>0,'building_facade'=>'north','address'=>'صنعاء حدة شارع 14',
            'latitude'=>15.3694,'longitude'=>44.191,'images'=>[UploadedFile::fake()->image('listing.jpg')]],$changes);
    }
}
