<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class UatHttpsMediaTest extends TestCase
{
    use RefreshDatabase;

    public function test_tls_termination_keeps_public_discovery_detail_and_marketplace_images_on_https(): void
    {
        [, $property, $image] = $this->listing();
        $root = 'https://real-estate-uat-api-frankfurt.onrender.com';
        $this->withHeaders(['X-Forwarded-Proto' => 'https']);
        $this->getJson('http://real-estate-uat-api-frankfurt.onrender.com/api/properties')
            ->assertOk()->assertJsonPath('data.0.main_image', $root.'/api/property-media/'.$image->id.'?variant=card');
        $this->getJson('http://real-estate-uat-api-frankfurt.onrender.com/api/properties/'.$property->id)
            ->assertOk()->assertJsonPath('data.images.0.url', $root.'/api/property-media/'.$image->id);
        $this->getJson('http://real-estate-uat-api-frankfurt.onrender.com/api/marketplace?'.http_build_query(['governorate' => 'صنعاء']))
            ->assertOk()->assertJsonPath('data.sections.latest.0.main_image', $root.'/api/property-media/'.$image->id.'?variant=card');
    }

    public function test_favorite_images_use_the_same_https_proxy_contract(): void
    {
        [$user, $property, $image] = $this->listing();
        $token = 'uat-https-fixture-token';
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token), 'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        DB::table('property_favorites')->insert(['user_id' => $user->id, 'property_id' => $property->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->withHeaders(['Authorization' => 'Bearer '.$token, 'X-Forwarded-Proto' => 'https'])
            ->getJson('http://real-estate-uat-api-frankfurt.onrender.com/api/favorites')->assertOk()
            ->assertJsonPath('data.0.property.main_image', 'https://real-estate-uat-api-frankfurt.onrender.com/api/property-media/'.$image->id);
    }

    public function test_forwarded_host_and_client_ip_cannot_change_the_request_or_throttle_identity(): void
    {
        Route::get('/__test/proxy-context', fn (Request $request) => response()->json([
            'secure' => $request->isSecure(), 'host' => $request->getHost(), 'ip' => $request->ip(),
        ]));
        $this->withServerVariables(['REMOTE_ADDR' => '127.0.0.1'])->withHeaders([
            'X-Forwarded-Proto' => 'https', 'X-Forwarded-For' => '198.51.100.99',
            'X-Forwarded-Host' => 'untrusted.example', 'X-Forwarded-Port' => '8443',
        ])->getJson('http://real-estate-uat-api-frankfurt.onrender.com/__test/proxy-context')
            ->assertOk()->assertJsonPath('secure', true)
            ->assertJsonPath('host', 'real-estate-uat-api-frankfurt.onrender.com')->assertJsonPath('ip', '127.0.0.1');
    }

    public function test_local_http_without_a_forwarded_scheme_keeps_its_original_url(): void
    {
        [, , $image] = $this->listing();
        $this->getJson('http://localhost/api/properties')->assertOk()
            ->assertJsonPath('data.0.main_image', 'http://localhost/api/property-media/'.$image->id.'?variant=card');
    }

    private function listing(): array
    {
        $user = User::create(['name' => 'UAT HTTPS fixture', 'email' => 'https-fixture@example.invalid', 'password' => 'fixture-only',
            'account_status' => 'active', 'identity_policy_version' => 2, 'phone_verified_at' => now(), 'profile_completed_at' => now()]);
        $property = Property::create(['user_id' => $user->id, 'title' => 'إعلان تجريبي', 'purpose' => 'rent', 'type' => 'shop',
            'price' => 100000, 'monthly_rent' => 100000, 'currency' => 'YER', 'area_m2' => 65, 'address' => 'صنعاء، موقع تجريبي',
            'latitude' => 15.3694, 'longitude' => 44.191, 'status' => 'published', 'review_status' => 'approved']);
        if (DB::getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        $image = PropertyImage::create(['property_id' => $property->id, 'path' => 'uat-https/fixture.jpg', 'sort_order' => 0, 'is_primary' => true]);
        return [$user, $property, $image];
    }
}
