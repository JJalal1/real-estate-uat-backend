<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PropertyIdentityV2Test extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_moving_pin_does_not_bypass_same_house_detection(): void
    {
        [, $first] = $this->user('identity-house-1@example.test', '+967733000001');
        [, $second] = $this->user('identity-house-2@example.test', '+967733000002');

        $a = $this->createReady($first, [
            'title' => 'فيلا حدة الأصلية', 'type' => 'villa', 'address' => 'صنعاء حدة شارع 14 بيت 18',
            'latitude' => 15.369400, 'longitude' => 44.191000, 'area_m2' => 420, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $b = $this->createReady($second, [
            'title' => 'فيلا للبيع', 'type' => 'villa', 'address' => 'صنعاء - حدة - شارع 14 - بيت 18',
            'latitude' => 15.369500, 'longitude' => 44.191060, 'area_m2' => 421, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);

        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")->assertStatus(409);
        $this->assertDatabaseHas('properties', ['id' => $b, 'duplicate_check_status' => 'confirmed_duplicate']);
    }

    public function test_adjacent_real_properties_are_allowed_when_identity_signals_differ(): void
    {
        [, $first] = $this->user('identity-neighbour-1@example.test', '+967733000003');
        [, $second] = $this->user('identity-neighbour-2@example.test', '+967733000004');
        $a = $this->createReady($first, [
            'title' => 'البيت الشمالي', 'address' => 'صنعاء بيت بوس شارع أ مبنى 10',
            'latitude' => 15.300000, 'longitude' => 44.210000, 'area_m2' => 180, 'area_value' => 180, 'bedrooms' => 3, 'bathrooms' => 2,
        ]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $b = $this->createReady($second, [
            'title' => 'البيت الجنوبي', 'address' => 'صنعاء بيت بوس شارع ب مبنى 11',
            'latitude' => 15.300700, 'longitude' => 44.210040, 'area_m2' => 340, 'area_value' => 340, 'bedrooms' => 5, 'bathrooms' => 4,
        ]);
        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")->assertOk();
    }

    public function test_same_building_same_unit_is_blocked_but_different_unit_is_allowed(): void
    {
        [, $first] = $this->user('identity-unit-1@example.test', '+967733000005');
        [, $second] = $this->user('identity-unit-2@example.test', '+967733000006');
        [, $third] = $this->user('identity-unit-3@example.test', '+967733000007');

        $common = [
            'type' => 'apartment', 'address' => 'صنعاء حدة شارع صفر مبنى النور',
            'building_reference' => 'عمارة النور 12', 'floor_number' => '3',
            'latitude' => 15.370000, 'longitude' => 44.190000, 'area_m2' => 130, 'bedrooms' => 3, 'bathrooms' => 2,
        ];
        $a = $this->createReady($first, array_merge($common, ['title' => 'شقة 7', 'unit_number' => '7']));
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $same = $this->createReady($second, array_merge($common, [
            'title' => 'نفس الشقة بدبوس محرك', 'unit_number' => '7', 'latitude' => 15.370070, 'longitude' => 44.190050,
        ]));
        $this->withHeaders($second)->postJson("/api/properties/$same/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->withHeaders($second)->postJson("/api/properties/$same/submit")->assertStatus(409);

        $different = $this->createReady($third, array_merge($common, ['title' => 'شقة 8', 'unit_number' => '8']));
        $this->withHeaders($third)->postJson("/api/properties/$different/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
        $this->withHeaders($third)->postJson("/api/properties/$different/submit")->assertOk();
    }

    public function test_land_boundary_prevents_pin_shift_and_allows_adjacent_parcel(): void
    {
        [, $first] = $this->user('identity-land-1@example.test', '+967733000008');
        [, $second] = $this->user('identity-land-2@example.test', '+967733000009');
        [, $third] = $this->user('identity-land-3@example.test', '+967733000010');

        $polygon = $this->polygon([[44.1800,15.3600],[44.1810,15.3600],[44.1810,15.3610],[44.1800,15.3610]]);
        $a = $this->createReady($first, ['type'=>'land','title'=>'قطعة أ','address'=>'حدة مخطط 5 قطعة 21','latitude'=>15.3605,'longitude'=>44.1805,'area_m2'=>1200,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$polygon]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $same = $this->createReady($second, ['type'=>'land','title'=>'نفس القطعة','address'=>'حدة مخطط 5 قطعة 21','latitude'=>15.3608,'longitude'=>44.1808,'area_m2'=>1200,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$polygon]);
        $this->withHeaders($second)->postJson("/api/properties/$same/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');

        $adjacentPolygon = $this->polygon([[44.1811,15.3600],[44.1821,15.3600],[44.1821,15.3610],[44.1811,15.3610]]);
        $adjacent = $this->createReady($third, ['type'=>'land','title'=>'قطعة مجاورة','address'=>'حدة مخطط 5 قطعة 22','latitude'=>15.3605,'longitude'=>44.1816,'area_m2'=>1190,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$adjacentPolygon]);
        $this->withHeaders($third)->postJson("/api/properties/$adjacent/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
    }

    public function test_ambiguous_case_requires_self_verification_then_routes_to_existing_review(): void
    {
        [, $first] = $this->user('identity-gray-1@example.test', '+967733000011');
        [, $second] = $this->user('identity-gray-2@example.test', '+967733000012');

        $a = $this->createReady($first, ['title'=>'منزل أول','address'=>'صنعاء حدة شارع الجامعة رقم 40','latitude'=>15.340000,'longitude'=>44.200000,'area_m2'=>250,'bedrooms'=>4,'bathrooms'=>3]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();
        $b = $this->createReady($second, ['title'=>'منزل قريب','address'=>'صنعاء حدة جوار السوق الخلفي','latitude'=>15.340300,'longitude'=>44.200120,'area_m2'=>252,'bedrooms'=>4,'bathrooms'=>3]);

        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'possible_duplicate')
            ->assertJsonPath('data.status', 'self_verification_required');
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertStatus(422)->assertJsonValidationErrors('duplicate_self_verification');

        $this->withHeaders($second)->postJson("/api/properties/$b/identity/self-verify", [
            'assert_different' => true,
            'difference_type' => 'different_address',
            'difference_note' => 'هذا منزل مستقل مجاور وله مدخل ورقم مبنى مختلف عن العقار الآخر.',
        ])->assertOk()->assertJsonPath('data.status', 'needs_support');

        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('listing_reviews', ['listing_id'=>$b,'action'=>'duplicate_suspected_after_self_verification']);
        $this->assertDatabaseHas('support_tasks', ['source_type'=>'listing_review','source_id'=>$b]);
    }

    public function test_identity_audit_journal_rejects_mutation(): void
    {
        [, $headers] = $this->user('identity-audit@example.test', '+967733000013');
        $id = $this->createReady($headers, ['title'=>'عقار تدقيق']);
        $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")->assertOk();
        $check = \DB::table('property_identity_checks')->where('property_id',$id)->first();
        $this->assertNotNull($check);
        $this->expectException(\Throwable::class);
        \DB::table('property_identity_checks')->where('id',$check->id)->update(['score'=>99]);
    }

    private function createReady(array $headers, array $overrides = []): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', $this->payload(array_merge([
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ], $overrides)));
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name'=>'Property Identity User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make(hash('sha256',$email.'|identity-v2')),
        ]);
        $role = Role::query()->where('key','registered_user')->firstOrFail();
        $user->roles()->sync([$role->id => ['assigned_by_user_id'=>null,'created_at'=>now()]]);
        $plain='identity_'.substr(hash('sha512',$email),0,76);
        $user->apiTokens()->create(['name'=>'identity-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function payload(array $overrides=[]): array
    {
        return array_merge([
            'listing_input_version'=>3,'title'=>'Property Identity V2','description'=>'Identity regression property.',
            'purpose'=>'sale','type'=>'house','tenure_type'=>'freehold','price'=>50000000,'currency'=>'YER',
            'area_m2'=>220,'area_value'=>220,'area_unit'=>'sqm','bedrooms'=>4,'bathrooms'=>3,'has_parking'=>true,'building_facade'=>'north',
            'address'=>'صنعاء حدة شارع رئيسي','latitude'=>15.3694,'longitude'=>44.1910,'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ],$overrides);
    }

    private function polygon(array $points): array
    {
        return ['type'=>'Polygon','coordinates'=>[array_merge($points,[$points[0]])]];
    }
}
