<?php
namespace Tests\Feature;

use App\Services\GeocodingGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** Synthetic public city-centre coordinates, never a person's home or live POI claim. */
class Branch2LocationTest extends TestCase
{
    use RefreshDatabase;
    private function address(): array { return ['address'=>['state'=>'محافظة صناعية','city'=>'مدينة صناعية','county'=>'مديرية صناعية','neighbourhood'=>'حي صناعي']]; }
    private function feature(array $changes=[]): array
    {
        return array_replace_recursive(['properties'=>['name'=>'قاعة اختبار صناعية','osm_key'=>'amenity','osm_value'=>'events_venue','osm_id'=>999999001,'osm_type'=>'N'],
            'geometry'=>['type'=>'Point','coordinates'=>[44.4,14.541]]],$changes);
    }
    private function point(array $extra=[]): array { return $extra+['latitude'=>14.54,'longitude'=>44.4]; }
    public function test_typed_address_never_promotes_a_neighborhood_or_display_prefix_to_street(): void
    {
        Http::fake(['*nominatim*'=>Http::response($this->address()+['display_name'=>'حي صناعي، مدينة صناعية']), '*photon*'=>Http::response(['features'=>[]])]);
        $response=$this->postJson('/api/regions/reverse-address',$this->point())->assertOk()
            ->assertJsonPath('data.city','مدينة صناعية')->assertJsonPath('data.district','مديرية صناعية')
            ->assertJsonPath('data.neighborhood','حي صناعي')->assertJsonPath('data.street',null)
            ->assertJsonPath('data.field_sources.neighborhood','nominatim')->assertJsonPath('data.requires_review',true);
        $this->assertStringContainsString('no-store',$response->headers->get('Cache-Control'));
    }
    public function test_landmarks_have_traceable_osm_source_and_calculated_straight_line_distance(): void
    {
        Http::fake(['*nominatim*'=>Http::response($this->address()), '*photon*'=>Http::response(['features'=>[$this->feature()]])]);
        $this->postJson('/api/regions/reverse-address',$this->point(['include_landmarks'=>true]))->assertOk()
            ->assertJsonCount(1,'data.landmarks')->assertJsonPath('data.landmarks.0.name','قاعة اختبار صناعية')
            ->assertJsonPath('data.landmarks.0.distance_m',111)->assertJsonPath('data.landmarks.0.distance_basis','straight_line')
            ->assertJsonPath('data.landmarks.0.source_url','https://www.openstreetmap.org/node/999999001')
            ->assertJsonPath('data.landmarks.0.confidence','mapped_feature_needs_review');
        Http::assertSent(fn($r)=>str_contains($r->url(),'include=') && str_contains($r->url(),'radius=1'));
    }
    public function test_missing_coordinates_far_or_unidentified_features_cannot_be_claimed_nearby(): void
    {
        $missing=$this->feature();unset($missing['geometry']);
        Http::fake(['*nominatim*'=>Http::response($this->address()), '*photon*'=>Http::response(['features'=>[
            $missing,$this->feature(['geometry'=>['coordinates'=>[45,16]]]),$this->feature(['properties'=>['name'=>'']]),
            $this->feature(['properties'=>['osm_id'=>null]]),$this->feature(['geometry'=>['coordinates'=>['bad',14.54]]]),
        ]])]);
        $this->postJson('/api/regions/reverse-address',$this->point(['include_landmarks'=>true]))->assertOk()->assertJsonCount(0,'data.landmarks');
    }
    public function test_database_cache_and_atomic_budget_are_shared_across_reverse_and_manager_search(): void
    {
        config(['geocoding.cache_store'=>'database']);
        Http::fake(['*'=>Http::response($this->address())]);
        $gateway=app(GeocodingGateway::class);$query=['lat'=>14.54,'lon'=>44.4];
        $this->assertSame('ok',$gateway->get('nominatim','/reverse',$query)['status']);
        $this->assertTrue($gateway->get('nominatim','/reverse',$query)['cached']);
        $this->assertSame('rate_limited',$gateway->get('nominatim','/search',['q'=>'مكان صناعي'])['status']);
        Http::assertSentCount(1);
        $this->travel(2)->seconds();
        $this->assertSame('ok',$gateway->get('nominatim','/search',['q'=>'مكان صناعي'])['status']);
        Http::assertSentCount(2);
        Http::assertSent(fn($r)=>str_contains($r->header('User-Agent')[0] ?? '','AqerYemen/'));
    }
    public function test_provider_failure_keeps_confirmed_point_and_allows_manual_address_without_fake_landmarks(): void
    {
        Http::fake(fn()=>throw new ConnectionException('Synthetic provider timeout'));
        $this->postJson('/api/regions/reverse-address',$this->point(['include_landmarks'=>true]))->assertOk()
            ->assertJsonPath('data.latitude',14.54)->assertJsonPath('data.longitude',44.4)
            ->assertJsonPath('data.provider_status','unavailable')->assertJsonPath('data.street',null)->assertJsonCount(0,'data.landmarks');
    }
    public function test_administrator_can_switch_or_disable_provider_without_a_mobile_release(): void
    {
        config(['geocoding.nominatim_url'=>'https://geocoder.example.test','geocoding.photon_url'=>'https://photon.example.test']);
        Http::fake(['*'=>Http::response($this->address())]);
        app(GeocodingGateway::class)->get('nominatim','/reverse',['lat'=>14.54,'lon'=>44.4]);
        Http::assertSent(fn($r)=>str_starts_with($r->url(),'https://geocoder.example.test/reverse'));
        config(['geocoding.enabled'=>false]);
        $this->assertSame('disabled',app(GeocodingGateway::class)->get('photon','/reverse',[])['status']);
        Http::assertSentCount(1);
    }
    public function test_declared_hierarchy_and_accuracy_are_private_checkpoint_data_and_round_trip(): void
    {
        // Reuse the normal approved account fixture without changing any live account.
        $user=\App\Models\User::create(['name'=>'اختبار موقع','email'=>'branch2-location@example.test','phone'=>'+12025554321',
            'password'=>\Illuminate\Support\Facades\Hash::make('fixture-pass'),'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $user->roles()->sync([\App\Models\Role::where('key','registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        \App\Models\AccountVerificationProfile::create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','submitted_at'=>now(),'reviewed_at'=>now()]);
        $token='synthetic-location-account';$user->apiTokens()->create(['name'=>'test','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addHour()]);
        $headers=['Authorization'=>'Bearer '.$token];$url='/api/listing-editor-drafts/'.\Illuminate\Support\Str::uuid();
        $payload=['editor_version'=>11,'draft_kind'=>'recovery','type'=>'apartment','purpose'=>'rent','location_method'=>'gps',
            'location_accuracy_m'=>67.5,'location_reduced_accuracy'=>true,'location_context'=>['unapproved_private_key'=>'drop me'],
            'fields'=>['city'=>'مدينة اختبار','district'=>'مديرية اختبار','neighborhood'=>'حي اختبار']];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        $this->withHeaders($headers)->getJson($url)->assertOk()->assertJsonPath('data.payload.location_accuracy_m',67.5)
            ->assertJsonPath('data.payload.location_reduced_accuracy',true)->assertJsonPath('data.payload.fields.neighborhood','حي اختبار')
            ->assertJsonMissingPath('data.payload.location_context.unapproved_private_key');
        $this->assertDatabaseCount('properties',0);
        $this->withHeaders(['Authorization'=>'Bearer other-synthetic-account'])->getJson($url)->assertUnauthorized();
    }
}
