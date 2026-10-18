<?php
namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\DynamicPropertySchema;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Str;
use Tests\TestCase;

class Wave6EditorDiscoveryTest extends TestCase
{
    use RefreshDatabase;

    public function test_partial_account_checkpoint_survives_without_creating_a_property_and_is_private(): void
    {
        [, $a]=$this->actor('a','broker');[, $b]=$this->actor('b','broker');
        $key=(string)Str::uuid();
        $payload=['type'=>'shop','purpose'=>'rent','step'=>2,'fields'=>['district'=>'حدة','area'=>'65','floor_number'=>'3'],'parking'=>'yes','facade'=>'north'];
        $this->withHeaders($a)->putJson('/api/listing-editor-drafts/'.$key,['payload'=>$payload,'expected_revision'=>0])
            ->assertOk()->assertJsonPath('data.revision',1)->assertJsonPath('data.payload.step',2)
            ->assertJsonPath('data.title','محل للإيجار - حدة')->assertJsonMissingPath('data.payload.parking')
            ->assertJsonMissingPath('data.payload.fields.floor_number');
        $this->assertDatabaseCount('properties',0);
        $this->withHeaders($b)->getJson('/api/listing-editor-drafts/'.$key)->assertNotFound();
        $this->withHeaders($b)->getJson('/api/listing-editor-drafts')->assertOk()->assertJsonCount(0,'data');
        $this->withHeaders($a)->getJson('/api/listing-editor-drafts/'.$key)->assertOk()->assertJsonPath('data.payload.fields.area','65');
        $this->withHeaders($a)->putJson('/api/listing-editor-drafts/'.$key,['payload'=>$payload,'expected_revision'=>0])
            ->assertConflict()->assertJsonPath('code','draft_revision_conflict');
        $this->withHeaders($a)->getJson('/api/listing-editor-drafts/'.$key)->assertJsonPath('data.revision',1);
    }

    public function test_private_real_photo_retry_and_cross_account_denial(): void
    {
        Storage::fake('local');
        [, $a]=$this->actor('photo','broker');[, $b]=$this->actor('photo-other','broker');
        $key=(string)Str::uuid();$imageKey=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($a)->putJson($url,['payload'=>['type'=>'shop','fields'=>[]],'expected_revision'=>0])->assertOk();
        $this->withHeaders($a)->post($url.'/images/'.$imageKey,['expected_revision'=>1,'image'=>UploadedFile::fake()->image('actual.jpg')])
            ->assertOk()->assertJsonPath('data.revision',2)->assertJsonCount(1,'data.images');
        $this->withHeaders($a)->post($url.'/images/'.$imageKey,['expected_revision'=>1,'image'=>UploadedFile::fake()->image('retry.jpg')])
            ->assertOk()->assertJsonPath('data.revision',2)->assertJsonCount(1,'data.images');
        $this->withHeaders($a)->get($url.'/images/'.$imageKey)->assertOk();
        $this->withHeaders($b)->get($url.'/images/'.$imageKey)->assertNotFound();
        $this->withHeaders($a)->deleteJson($url.'/images/'.$imageKey,['expected_revision'=>1])->assertConflict();
        $this->withHeaders($a)->deleteJson($url)->assertOk();
        $this->assertCount(0,Storage::disk('local')->allFiles('editor-drafts'));
    }

    public function test_multiple_drafts_keep_previous_progress_and_personal_slot_is_server_enforced(): void
    {
        [, $broker]=$this->actor('multi','broker');[, $owner]=$this->actor('personal','owner');
        $first=(string)Str::uuid();$second=(string)Str::uuid();
        foreach([$first,$second] as $key) $this->withHeaders($broker)->putJson('/api/listing-editor-drafts/'.$key,['payload'=>['step'=>1,'fields'=>[]],'expected_revision'=>0])->assertOk();
        $this->withHeaders($broker)->getJson('/api/listing-editor-drafts')->assertJsonCount(2,'data');
        $this->withHeaders($owner)->putJson('/api/listing-editor-drafts/'.$first,['payload'=>['fields'=>[]],'expected_revision'=>0])->assertOk();
        $this->withHeaders($owner)->putJson('/api/listing-editor-drafts/'.$second,['payload'=>['fields'=>[]],'expected_revision'=>0])->assertConflict();
        $this->withHeaders($owner)->postJson('/api/ai/listing-draft',['mode'=>'copy','facts'=>['type'=>'shop'],'editor_draft_key'=>$first])->assertOk();
        $this->withHeaders($owner)->postJson('/api/ai/listing-draft',['mode'=>'copy','facts'=>['type'=>'shop'],'editor_draft_key'=>$second])->assertConflict();
        $this->assertDatabaseCount('properties',0);
    }

    public function test_personal_owner_can_review_rental_requirements_for_their_existing_account_draft(): void
    {
        [, $headers]=$this->actor('owner-requirements','owner');$key=(string)Str::uuid();
        $this->withHeaders($headers)->putJson('/api/listing-editor-drafts/'.$key,
            ['payload'=>['type'=>'shop','purpose'=>'rent','fields'=>[]],'expected_revision'=>0])->assertOk();
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-key','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>200]);
        \Illuminate\Support\Facades\Http::fake(['generativelanguage.googleapis.com/*'=>\Illuminate\Support\Facades\Http::response(
            ['candidates'=>[['content'=>['parts'=>[['text'=>json_encode(['order'=>[0]])]]]]]],200)]);
        $input=['rental_conditions'=>[['kind'=>'advance','months'=>3]]];
        $this->withHeaders($headers)->postJson('/api/ai/rental-conditions',$input)->assertConflict();
        $this->withHeaders($headers)->postJson('/api/ai/rental-conditions',$input+['editor_draft_key'=>$key])
            ->assertOk()->assertJsonPath('data.requires_review',true)->assertJsonPath('data.rental_conditions.0.months',3);
        \Illuminate\Support\Facades\Http::assertSentCount(1);
        $this->assertDatabaseCount('properties',0);$this->assertDatabaseCount('property_sai_terms',0);
    }

    public function test_unverified_and_suspended_accounts_cannot_save_or_upload(): void
    {
        [$u,$a]=$this->actor('ordinary',null);$key=(string)Str::uuid();
        $this->withHeaders($a)->putJson('/api/listing-editor-drafts/'.$key,['payload'=>['fields'=>[]],'expected_revision'=>0])->assertForbidden();
        [$u,$a]=$this->actor('suspended','broker');$u->update(['account_status'=>'suspended']);
        $this->withHeaders($a)->putJson('/api/listing-editor-drafts/'.$key,['payload'=>['fields'=>[]],'expected_revision'=>0])->assertForbidden();
    }

    public function test_schema_is_dynamic_for_all_approved_types_and_previous_answers(): void
    {
        $schema=app(DynamicPropertySchema::class);
        foreach(array_keys($schema->definition()['types']) as $type)foreach(['sale','rent'] as $purpose){
            $facts=['type'=>$type,'purpose'=>$purpose,'area_value'=>100,'area_unit'=>'sqm','floor_number'=>'3','unit_number'=>'2','has_parking'=>true,'has_elevator'=>true,'building_facade'=>'north','bedrooms'=>3,'bathrooms'=>2];
            $clean=$schema->facts($facts);
            foreach($schema->definition()['fields'] as $key=>$_)if(!$schema->applies($key,$facts))$this->assertArrayNotHasKey($key,$clean);
            if($type==='shop')$this->assertSame(['area_value'],$schema->required($facts));
        }
        $this->assertSame('0',$schema->normalizeFloor('الأرضي'));
        $this->assertSame('3',$schema->normalizeFloor('الدور الثالث'));
        $this->assertArrayNotHasKey('unit_number',$schema->facts(['type'=>'apartment','unit_occupies_entire_floor'=>true,'unit_number'=>'4']));
        $shop=$schema->facts(['type'=>'shop','area_value'=>2,'area_unit'=>'libna_sanaani']);
        $this->assertEquals(88.88,$shop['area_value']);$this->assertSame('sqm',$shop['area_unit']);
        $this->assertSame(['type'=>'shop'], $schema->filters(['type'=>'shop','floor_number'=>'3','has_parking'=>true,'building_facade'=>'north']));
    }
    public function test_promotion_uses_the_normal_listing_path_and_never_duplicates_uploaded_photos(): void
    {
        Storage::fake('local'); Storage::fake('public');
        [, $headers]=$this->actor('promote','broker'); $key=(string)Str::uuid();$photo=(string)Str::uuid();
        $url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($headers)->putJson($url,['expected_revision'=>0,'payload'=>['type'=>'shop','purpose'=>'rent','image_order'=>[$photo],'fields'=>['area'=>'65']]])->assertOk();
        $this->withHeaders($headers)->post($url.'/images/'.$photo,['expected_revision'=>1,'image'=>UploadedFile::fake()->image('real.jpg')])->assertOk();
        $input=['listing_input_version'=>8,'title'=>'محل للإيجار في حدة','description'=>'محل مساحته 65 مترًا مربعًا.','type'=>'shop','purpose'=>'rent',
            'price'=>75000,'monthly_rent'=>75000,'currency'=>'YER','area_value'=>65,'area_unit'=>'sqm','address'=>'صنعاء حدة شارع 14',
            'latitude'=>15.3694,'longitude'=>44.191,'editor_draft_key'=>$key,'editor_draft_revision'=>2];
        $id=(int)$this->withHeaders($headers)->postJson('/api/properties',$input)->assertCreated()->assertJsonCount(1,'data.images')->json('data.id');
        $this->assertDatabaseHas('properties',['id'=>$id,'type'=>'shop','status'=>'draft','floor_number'=>null,'unit_number'=>null,'has_parking'=>null,'building_facade'=>null]);
        $this->withHeaders($headers)->getJson($url)->assertJsonPath('data.property_id',$id)->assertJsonPath('data.revision',3)->assertJsonCount(0,'data.images');
        $this->withHeaders($headers)->postJson('/api/properties',$input)->assertConflict();
        $input['editor_draft_revision']=3;
        $this->withHeaders($headers)->postJson('/api/properties',$input)->assertOk()->assertJsonPath('data.id',$id)->assertJsonCount(1,'data.images');
        $this->assertDatabaseCount('properties',1);$this->assertDatabaseCount('property_images',1);$this->assertDatabaseCount('property_sai_terms',0);
        $image=\App\Models\PropertyImage::query()->firstOrFail();
        $this->withHeaders(['Authorization'=>''])->get('/api/property-media/'.$image->id)->assertNotFound();
        $this->withHeaders($headers)->get('/api/property-media/'.$image->id)->assertOk();
        $this->withHeaders($headers)->deleteJson($url)->assertOk();
        $this->assertDatabaseHas('properties',['id'=>$id,'status'=>'archived']);$this->assertDatabaseCount('property_images',1);
        Storage::disk('local')->assertExists($image->path);
    }

    public function test_broker_directory_conversation_reuses_private_threads_and_has_no_implicit_messages_or_financial_terms(): void
    {
        [$broker,$b]=$this->actor('chat-broker','broker');[$customer,$c]=$this->actor('chat-customer',null);[, $outsider]=$this->actor('chat-outsider',null);
        $url='/api/brokers/'.$broker->id.'/conversation';
        $id=$this->withHeaders($c)->postJson($url)->assertCreated()->assertJsonPath('data.context_type','broker')->assertJsonPath('data.property_id',null)->json('data.id');
        $this->withHeaders($c)->postJson($url)->assertOk()->assertJsonPath('data.id',$id);
        $this->assertDatabaseCount('message_threads',1);$this->assertDatabaseCount('message_thread_participants',2);$this->assertDatabaseCount('private_messages',0);
        $this->withHeaders($outsider)->getJson('/api/messages/threads/'.$id)->assertNotFound();
        $this->withHeaders($b)->getJson('/api/messages/threads/'.$id)->assertOk()->assertJsonCount(0,'data.messages');
        $this->withHeaders($b)->postJson($url)->assertUnprocessable();
        $this->withHeaders($c)->postJson('/api/brokers/'.$customer->id.'/conversation')->assertUnprocessable();
        $broker->update(['account_status'=>'suspended']);$this->withHeaders($c)->postJson($url)->assertNotFound();
        $this->assertDatabaseCount('properties',0);$this->assertDatabaseCount('property_sai_terms',0);$this->assertDatabaseCount('viewing_bookings',0);
    }

    public function test_listing_ai_extracts_only_explicit_sai_and_rental_conditions_and_never_relabels_foreign_fixed_money(): void
    {
        [, $headers]=$this->actor('ai-sai','broker');
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-key','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>200]);
        $fields=['type'=>'shop','purpose'=>'rent','monthly_rent'=>75000,'floor_number'=>'3','has_parking'=>true,'area_value'=>65,'area_unit'=>'sqm',
            'sai_amount_type'=>'percentage','broker_sai_rate_percent'=>50,'rental_conditions'=>[['kind'=>'advance','months'=>3]]];
        $response=fn($f)=>['candidates'=>[['content'=>['parts'=>[['text'=>json_encode(['fields'=>$f],JSON_UNESCAPED_UNICODE)]]]]]];
        $foreignFields=['type'=>'shop','purpose'=>'rent','monthly_rent'=>100,'currency'=>'USD','sai_amount_type'=>'fixed','fixed_sai_amount'=>10];
        \Illuminate\Support\Facades\Http::fake(['generativelanguage.googleapis.com/*'=>\Illuminate\Support\Facades\Http::sequence()->push($response($fields))->push($response($foreignFields))]);
        $this->withHeaders($headers)->postJson('/api/ai/listing-draft',['mode'=>'prepare','message'=>'محل للإيجار مساحته 65 مترًا، الإيجار 75 ألف ريال والسعي 50%، مقدم ثلاثة أشهر','facts'=>(object)[]])
            ->assertOk()->assertJsonPath('data.fields.broker_sai_rate_percent',50)->assertJsonPath('data.fields.rental_conditions.0.months',3)
            ->assertJsonMissingPath('data.fields.floor_number')->assertJsonMissingPath('data.fields.has_parking')->assertJsonPath('data.requires_review',true);
        $this->withHeaders($headers)->postJson('/api/ai/listing-draft',['mode'=>'prepare','message'=>'محل بإيجار مئة دولار وسعي عشرة دولارات','facts'=>(object)[]])
            ->assertOk()->assertJsonMissingPath('data.fields.monthly_rent')->assertJsonMissingPath('data.fields.fixed_sai_amount')->assertJsonMissingPath('data.fields.sai_amount_type');
        \Illuminate\Support\Facades\Http::assertSentCount(2);
        $this->assertDatabaseCount('properties',0);$this->assertDatabaseCount('property_sai_terms',0);
    }

    public function test_broker_closed_counts_and_home_nearby_sections_are_real_recorded_data(): void
    {
        [$broker,$headers]=$this->actor('stats','broker');
        $rows=[];
        foreach([['sale','sold'],['rent','rented'],['sale','available']] as [$purpose,$availability]){
            $property=$this->listing($broker);$property->forceFill(['purpose'=>$purpose,'monthly_rent'=>$purpose==='rent'?100000:null])->save();
            $this->withHeaders($headers)->putJson('/api/properties/'.$property->id.'/sai',['broker_sai_rate_percent'=>0,'sai_payer'=>$purpose==='rent'?'tenant':'buyer'])->assertOk();
            $property->refresh()->forceFill(['status'=>'published','review_status'=>'approved','availability_status'=>$availability,'published_at'=>now()])->save();$rows[]=$property;
        }
        [$sold,$rented,$active]=$rows;
        $this->withHeaders(['Authorization'=>'']);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertOk()->assertJsonPath('data.sold_listings',1)->assertJsonPath('data.rented_listings',1)->assertJsonPath('data.completed_deals',0);
        $r=$this->getJson('/api/marketplace?latitude=15.3694&longitude=44.191')->assertOk()->assertJsonCount(1,'data.sections.nearby')->assertJsonPath('data.sections.nearby.0.id',$active->id);
        $this->assertSame('nearby',$r->json('data.section_order.0'));
        $this->assertNotContains($sold->id,array_column($r->json('data.sections.nearby'),'id'));
    }

    public function test_current_wave_apartment_floor_bounds_cover_listing_checkpoints_and_ai(): void
    {
        [, $headers]=$this->actor('floor-bounds','broker');
        $input=['listing_input_version'=>8,'title'=>'شقة للإيجار في حدة','description'=>'','type'=>'apartment','purpose'=>'rent',
            'price'=>100000,'monthly_rent'=>100000,'currency'=>'YER','bedrooms'=>3,'bathrooms'=>2,'has_parking'=>false,
            'building_facade'=>'north','address'=>'صنعاء حدة شارع 14','latitude'=>15.3694,'longitude'=>44.191];
        foreach(['8','-1','50','الثامن'] as $floor) {
            $this->withHeaders($headers)->postJson('/api/properties',$input+['floor_number'=>$floor])->assertUnprocessable()->assertJsonValidationErrors('floor_number');
            $this->withHeaders($headers)->putJson('/api/listing-editor-drafts/'.Str::uuid(),['expected_revision'=>0,
                'payload'=>['type'=>'apartment','fields'=>['floor_number'=>$floor]]])->assertUnprocessable()->assertJsonValidationErrors('fields.floor_number');
        }
        foreach(['0','7','الأرضي','السابع'] as $floor) {
            $this->withHeaders($headers)->putJson('/api/listing-editor-drafts/'.Str::uuid(),['expected_revision'=>0,
                'payload'=>['type'=>'apartment','fields'=>['floor_number'=>$floor]]])->assertOk();
        }
        $this->withHeaders($headers)->postJson('/api/ai/listing-description',['facts'=>['type'=>'apartment','floor_number'=>'8']])
            ->assertUnprocessable()->assertJsonValidationErrors('facts.floor_number');
        $this->assertDatabaseCount('properties',0);
        $this->assertCount(8,app(DynamicPropertySchema::class)->definition()['apartment_floors']);
    }

    public function test_description_provider_429_keeps_retry_after_and_spends_exactly_one_request(): void
    {
        [, $headers]=$this->actor('description-rate','broker');
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-key','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>200]);
        \Illuminate\Support\Facades\Http::fake(['generativelanguage.googleapis.com/*'=>\Illuminate\Support\Facades\Http::response(
            ['error'=>['message'=>'private-provider-quota']],429,['Retry-After'=>'90'])]);
        $response=$this->withHeaders($headers)->postJson('/api/ai/listing-description',['facts'=>['type'=>'house','purpose'=>'sale']])
            ->assertStatus(429)->assertHeader('Retry-After','90')->assertJsonPath('retry_after_seconds',90);
        \Illuminate\Support\Facades\Http::assertSentCount(1);
        $this->assertStringNotContainsString('private-provider-quota',$response->getContent());
        $this->assertDatabaseHas('ai_daily_usage',['day'=>now('UTC')->toDateString(),'request_count'=>1]);
        $this->assertDatabaseCount('properties',0);$this->assertDatabaseCount('property_sai_terms',0);
    }

    public function test_description_daily_budget_waits_until_utc_reset_without_an_outbound_request(): void
    {
        $this->travelTo(\Illuminate\Support\Carbon::parse('2026-10-18T23:59:00Z'));
        [, $headers]=$this->actor('description-budget','broker');
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-key','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>1]);
        \Illuminate\Support\Facades\DB::table('ai_daily_usage')->insert(['day'=>'2026-10-18','request_count'=>1]);
        \Illuminate\Support\Facades\Http::fake();
        $this->withHeaders($headers)->postJson('/api/ai/listing-description',['facts'=>['type'=>'house']])
            ->assertStatus(429)->assertHeader('Retry-After','60');
        \Illuminate\Support\Facades\Http::assertNothingSent();
    }

    private function actor(string $name, ?string $type): array
    {
        $user = User::create(['name' => 'دلال اختباري', 'email' => $name.'@draft.example.test',
            'phone' => '+1202555'.substr(hash('sha256', $name), 0, 5), 'password' => Hash::make('fixture-pass'),
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'identity_policy_version' => 2, 'account_status' => 'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]]);
        if ($type) AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type,
            'status' => 'approved', 'submitted_at' => now(), 'reviewed_at' => now()]);
        $token = 'draft_fixture_'.$name;
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function listing(User $user): Property
    {
        $property=Property::create(['user_id' => $user->id, 'title' => 'عنوان محفوظ', 'description' => 'وصف محفوظ',
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 50000000, 'currency' => 'YER', 'area_m2' => 140,
            'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء، حدة', 'latitude' => 15.3694, 'longitude' => 44.1910,
            'status' => 'draft', 'review_status' => 'draft']);
        if(\Illuminate\Support\Facades\DB::getDriverName()==='pgsql') \Illuminate\Support\Facades\DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(?, ?),4326)::geography WHERE id=?',[(float)$property->longitude,(float)$property->latitude,$property->id]);
        return $property;

    }
}
