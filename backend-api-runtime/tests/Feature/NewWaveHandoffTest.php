<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\DynamicPropertySchema;
use App\Services\ListingAiService;
use App\Services\ListingContactService;
use App\Services\ListingDescriptionComposer;
use App\Services\ListingEditorDraftService;
use App\Services\RentalConditionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class NewWaveHandoffTest extends TestCase
{
    use RefreshDatabase;

    private function actor(string $key): array
    {
        $user=User::create(['name'=>'دلال اختبار','email'=>$key.'@wave9.example.test','phone'=>$key==='foreign'?'+967781234567':'+967771234567',
            'password'=>Hash::make('fixture-only'),'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $user->roles()->sync([Role::where('key','registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        AccountVerificationProfile::create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','reviewed_at'=>now()]);
        $token='wave9_fixture_'.$key;
        $user->apiTokens()->create(['name'=>'fixture','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$token,'Accept'=>'application/json']];
    }

    public function test_structure_roundtrip_hides_retired_elevator_and_does_not_change_the_account(): void
    {
        [$user,$headers]=$this->actor('structure');
        $property=Property::create(['user_id'=>$user->id,'title'=>'عمارة اختبار','purpose'=>'sale','type'=>'building','price'=>10000000,'currency'=>'YER',
            'address'=>'صنعاء، حدة','latitude'=>15.37,'longitude'=>44.19,'status'=>'draft','review_status'=>'draft','has_elevator'=>true]);
        $this->withHeaders($headers)->postJson('/api/properties/'.$property->id,[
            'listing_input_version'=>9,'floors_count'=>3,'units_per_floor'=>'[2,3,2]',
            'area_value'=>200,'area_unit'=>'sqm','tenure_type'=>'freehold','has_parking'=>false,'building_facade'=>'north',
            'contact_phone'=>'+967 731234567','contact_whatsapp'=>'781234567',
        ])->assertOk()->assertJsonPath('data.floors_count',3)->assertJsonPath('data.units_per_floor',[2,3,2]);
        $property->refresh();
        $this->assertSame([2,3,2],$property->units_per_floor);
        $this->assertSame('731234567',$property->contact_phone);
        $this->assertSame('+967771234567',$user->fresh()->phone);
        $this->assertSame(15.37,$property->latitude);
        $data=$this->withHeaders($headers)->getJson('/api/properties/'.$property->id)->assertOk()->json('data');
        $this->assertNull($data['has_elevator'] ?? null);
        [, $foreign]=$this->actor('foreign');
        $this->withHeaders($foreign)->postJson('/api/properties/'.$property->id,['floors_count'=>7])->assertForbidden();
        $this->assertSame(3,$property->fresh()->floors_count);
    }

    public function test_type_scoping_and_partial_drafts_keep_each_real_floor_without_inventing_counts(): void
    {
        $schema=app(DynamicPropertySchema::class);
        $this->assertContains('units_per_floor',$schema->required(['type'=>'house','listing_input_version'=>9]));
        $this->assertNotContains('units_per_floor',$schema->required(['type'=>'house','listing_input_version'=>8]));
        $this->assertSame([], $schema->filters(['has_elevator'=>true]));
        $this->assertFalse($schema->applies('has_elevator',[]));
        $clean=$schema->facts(['type'=>'shop','floors_count'=>4,'units_per_floor'=>[2,2,2,2],'shop_openings'=>3,'has_elevator'=>true]);
        $this->assertSame(['type'=>'shop','shop_openings'=>3],$clean);
        $draft=app(ListingEditorDraftService::class)->clean(['editor_version'=>9,'type'=>'house','units_per_floor'=>['2','','3'],'same_floor_units'=>false,
            'fields'=>['floors_count'=>'3','shop_openings'=>'4','description'=>'حوش ومدخل مستقل']]);
        $this->assertSame(['2','','3'],$draft['units_per_floor']);
        $this->assertArrayNotHasKey('shop_openings',$draft['fields']);
        $copy=app(ListingDescriptionComposer::class)->compose(['type'=>'house','floors_count'=>3,'units_per_floor'=>[2,1,2],'has_elevator'=>true]);
        $this->assertStringContainsString('2، 1، 2',$copy['description']);
        $this->assertStringNotContainsString('مصعد',$copy['description']);
        $this->expectException(ValidationException::class);
        $schema->validateStructure(['type'=>'building','floors_count'=>3,'units_per_floor'=>[2,2]]);
    }

    public function test_listing_phone_policy_is_local_and_configurable_without_changing_auth_rules(): void
    {
        $service=app(ListingContactService::class);
        foreach (['70','71','73','77','78'] as $prefix) $this->assertSame($prefix.'1234567',$service->normalize('+967'.$prefix.'1234567','contact_phone',true));
        $this->assertSame('771234567',$service->normalize('٠٠٩٦٧٧٧١٢٣٤٥٦٧','contact_phone',true));
        $this->assertNull($service->normalize('','contact_whatsapp'));
        config(['listing_contacts.yemen_mobile_prefixes'=>['79']]);
        $this->assertSame('791234567',$service->normalize('791234567','contact_phone',true));
        $this->expectException(ValidationException::class);
        $service->normalize('+12025550103','contact_phone',true);
    }

    public function test_selected_rental_summary_has_actual_duration_and_no_unselected_terms(): void
    {
        $this->assertSame(['إيجار مقدم: 3 أشهر','مدة العقد: سنة واحدة','شرط خاص: لا يسمح بالتأجير من الباطن'],
            app(RentalConditionService::class)->sentences([['kind'=>'advance','months'=>3],['kind'=>'duration','months'=>12],['kind'=>'special','text'=>'لا يسمح بالتأجير من الباطن']]));
    }

    public function test_explicit_structure_counts_are_preserved_without_a_model_and_ambiguity_stays_missing(): void
    {
        $parser=app(\App\Services\ExplicitListingFacts::class);
        $facts=$parser->extract('عمارة للبيع، ثلاثة أدوار، شقتان في كل دور');
        $this->assertSame(3,$facts['floors_count']);
        $this->assertSame([2,2,2],$facts['units_per_floor']);
        $shop=$parser->extract('محل للإيجار، 3 فتحات');
        $this->assertSame(3,$shop['shop_openings']);
        $unclear=$parser->extract('عمارة من ثلاثة أدوار أو أربعة أدوار');
        $this->assertArrayNotHasKey('floors_count',$unclear);
        $this->assertArrayNotHasKey('units_per_floor',$unclear);
    }

    public function test_description_improvement_only_reorders_literal_details_and_rejects_invented_copy(): void
    {
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-only','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>200]);
        Http::preventStrayRequests();
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::sequence()
            ->push(['candidates'=>[['content'=>['parts'=>[['text'=>json_encode(['detail_order'=>[1,0]])]]]]]])
            ->push(['candidates'=>[['content'=>['parts'=>[['text'=>json_encode(['detail_order'=>[0,1],'description'=>'قصر فاخر بمسبح'])]]]]]])]);
        $result=app(ListingAiService::class)->description([],"مدخل مستقل. حوش واسع. مدخل مستقل.");
        $this->assertSame('حوش واسع. مدخل مستقل.',$result['description']);
        $this->assertTrue($result['requires_review']);
        $this->assertDatabaseCount('properties',0);
        try { app(ListingAiService::class)->description([],"مدخل مستقل. حوش واسع."); $this->fail('Invented model copy must be rejected'); }
        catch (\Illuminate\Http\Exceptions\HttpResponseException $error) { $this->assertSame(503,$error->getResponse()->getStatusCode()); }
        Http::assertSentCount(2);
    }
}
