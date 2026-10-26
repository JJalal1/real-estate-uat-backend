<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class LaunchReadinessWave4Test extends TestCase
{
    use RefreshDatabase;

    public function test_release_metadata_is_public_and_normalized(): void
    {
        Config::set('release.android.minimum_supported_build', 1100);
        Config::set('release.android.latest_build', 1124);
        Config::set('release.android.store_url', 'https://play.google.com/store/apps/details?id=example');

        $this->getJson('/api/release')
            ->assertOk()
            ->assertJsonPath('data.platform', 'android')
            ->assertJsonPath('data.minimum_supported_build', 1100)
            ->assertJsonPath('data.latest_build', 1124)
            ->assertJsonPath('data.store_url', 'https://play.google.com/store/apps/details?id=example');
    }

    public function test_android_asset_links_are_empty_until_signing_identity_is_configured(): void
    {
        Config::set('app_links.android.package_name', 'com.aqer.yemen');
        Config::set('app_links.android.sha256_cert_fingerprints', []);

        $this->getJson('/.well-known/assetlinks.json')
            ->assertOk()
            ->assertExactJson([]);

        $fingerprint=implode(':',array_fill(0,32,'AA'));
        Config::set('app_links.android.sha256_cert_fingerprints', [$fingerprint]);
        $this->getJson('/.well-known/assetlinks.json')
            ->assertOk()
            ->assertJsonPath('0.relation.0', 'delegate_permission/common.handle_all_urls')
            ->assertJsonPath('0.target.namespace', 'android_app')
            ->assertJsonPath('0.target.package_name', 'com.aqer.yemen')
            ->assertJsonPath('0.target.sha256_cert_fingerprints.0', $fingerprint);
    }

    public function test_malformed_or_ambiguous_association_identity_is_never_published(): void
    {
        foreach ([['com.example.uat',['AA:BB:CC']],['invalid/package',[implode(':',array_fill(0,32,'AA'))]],
            ['com.example.uat',[implode(':',array_fill(0,32,'AA')),'bad']],['com.example.uat','invalid']] as [$package,$fingerprints]) {
            config(['app_links.android.package_name'=>$package,'app_links.android.sha256_cert_fingerprints'=>$fingerprints]);
            $this->getJson('/.well-known/assetlinks.json')->assertOk()->assertExactJson([]);
        }
    }

    public function test_public_property_share_page_only_serves_published_available_listing(): void
    {
        $owner = User::query()->create([
            'name' => 'Launch Owner',
            'email' => 'launch-owner@example.test',
            'password' => Hash::make('StrongPass123!'),
            'account_status' => User::STATUS_ACTIVE,
        ]);

        $property = Property::query()->create([
            'user_id' => $owner->id,
            'title' => 'شقة إطلاق',
            'description' => 'عقار صالح للمشاركة العامة.',
            'purpose' => 'sale',
            'type' => 'apartment',
            'price' => 25000000,
            'currency' => 'YER',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'address' => 'صنعاء',
            'status' => 'published',
            'review_status' => 'approved',
            'availability_status' => 'available',
            'published_at' => now(),
        ]);

        $this->get('/l/properties/'.$property->id)
            ->assertOk()
            ->assertSee('شقة إطلاق')
            ->assertSee('realestate://app/properties/'.$property->id, false);

        $property->forceFill(['status' => 'draft'])->save();
        $this->get('/l/properties/'.$property->id)->assertNotFound();
    }
}
