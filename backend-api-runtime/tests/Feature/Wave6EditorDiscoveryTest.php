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
        return Property::create(['user_id' => $user->id, 'title' => 'عنوان محفوظ', 'description' => 'وصف محفوظ',
            'purpose' => 'sale', 'type' => 'apartment', 'price' => 50000000, 'currency' => 'YER', 'area_m2' => 140,
            'bedrooms' => 3, 'bathrooms' => 2, 'address' => 'صنعاء، حدة', 'latitude' => 15.3694, 'longitude' => 44.1910,
            'status' => 'draft', 'review_status' => 'draft']);
    }
}
