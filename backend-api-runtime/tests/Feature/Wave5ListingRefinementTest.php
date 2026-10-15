<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use App\Services\PropertyIdentityService;
use App\Services\PropertySaiService;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class Wave5ListingRefinementTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
        $this->travelTo(now()->startOfSecond());
    }

    public function test_fixed_amount_is_authorized_bounded_and_not_recomputed_as_a_percentage(): void
    {
        [$broker, $headers] = $this->actor('fixed');
        [, $otherHeaders] = $this->actor('outside');
        $id = $this->createListing($headers);
        $input = ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>30000, 'defer_platform_terms'=>true];
        $this->withHeaders($otherHeaders)->putJson("/api/properties/$id/sai", $input)->assertForbidden();
        $response = $this->withHeaders($headers)->putJson("/api/properties/$id/sai", $input)->assertOk()
            ->assertJsonPath('data.sai.amount_type', 'fixed')
            ->assertJsonPath('data.sai.fixed_amount', 30000)
            ->assertJsonPath('data.sai.currency', 'YER')
            ->assertJsonPath('data.sai.rate_percent', null)
            ->assertJsonPath('data.sai_management.platform_terms_status', 'pending');
        $termId = $response->json('data.sai_management.term_id');
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", $input)->assertOk()
            ->assertJsonPath('data.sai_management.term_id', $termId);
        foreach ([
            array_merge($input, ['broker_sai_rate_percent'=>0]),
            array_merge($input, ['fixed_sai_amount'=>100000.01]),
            array_merge($input, ['fixed_sai_amount'=>-1]),
            array_merge($input, ['fixed_sai_amount'=>0.001]),
            ['sai_amount_type'=>'percentage', 'fixed_sai_amount'=>20000, 'broker_sai_rate_percent'=>30],
        ] as $bad) {
            $this->withHeaders($headers)->putJson("/api/properties/$id/sai", $bad)->assertUnprocessable();
        }
        $term = PropertySaiTerm::findOrFail($termId);
        $this->assertSame(['total_sai'=>30000.0, 'platform_share'=>6000.0, 'broker_share'=>24000.0],
            app(PropertySaiService::class)->calculateSaiAmount($term, 80000));
        Property::findOrFail($id)->forceFill(['status'=>'published', 'review_status'=>'approved', 'published_at'=>now()])->save();
        $this->withHeaders(['Authorization'=>''])->getJson("/api/properties/$id/sai")->assertOk()
            ->assertJsonPath('data.sai.display_text', 'السعي 30000 YER - يتحمله المستأجر')
            ->assertJsonMissingPath('data.sai_management');
        $this->getJson("/api/properties/$id")->assertOk()
            ->assertJsonPath('data.price_display_note', 'السعي 30000 YER')
            ->assertJsonPath('data.sai.amount', 30000);
        $this->assertDatabaseCount('property_sai_terms', 1);
        $this->assertDatabaseCount('property_sai_attestations', 0);
    }

    public function test_frozen_fixed_fee_survives_new_listing_terms_and_requires_customer_confirmation(): void
    {
        [$broker, $headers] = $this->actor('frozen');
        [, $customerHeaders] = $this->actor('customer', null);
        $id = $this->createListing($headers);
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",
            ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>40000, 'defer_platform_terms'=>true])->assertOk();
        $old = PropertySaiTerm::findOrFail(Property::findOrFail($id)->current_sai_term_id);
        $oldRaw = $old->getRawOriginal();
        $this->publish($id);
        $thread = (int) $this->withHeaders($customerHeaders)->postJson("/api/properties/$id/conversation")->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson("/api/properties/$id", ['monthly_rent'=>120000])->assertOk();
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",
            ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>50000, 'defer_platform_terms'=>true])->assertOk();
        $currentId = Property::findOrFail($id)->current_sai_term_id;
        $this->publish($id);
        $challenge = $this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal", ['basis_amount'=>110000])
            ->assertConflict()->assertJsonPath('data.sai_term_id', $old->id);
        $this->assertStringContainsString('مبلغ ثابت 40000 YER', $challenge->json('data.text'));
        $this->assertStringNotContainsString('50000', $challenge->json('data.text'));
        $this->assertDatabaseCount('broker_deal_outcomes', 0);
        $this->withHeaders($headers)->postJson("/api/properties/$id/sai-attestation", ['accepted'=>true, 'sai_term_id'=>$old->id])->assertOk();
        $deal = (int) $this->withHeaders($headers)->postJson("/api/broker/customers/$thread/completed-deal", ['basis_amount'=>110000])
            ->assertCreated()->json('data.id');
        $this->assertDatabaseCount('property_deal_financial_terms', 0);
        $this->withHeaders($customerHeaders)->postJson("/api/broker/deals/$deal/decision", ['confirmed'=>true])->assertOk();
        $this->assertDatabaseHas('property_deal_financial_terms', ['broker_deal_outcome_id'=>$deal,
            'sai_total_amount'=>40000, 'platform_share_amount'=>8000, 'advertiser_sai_share_amount'=>32000]);
        $this->assertDatabaseHas('properties', ['id'=>$id, 'current_sai_term_id'=>$currentId]);
        $this->assertDatabaseHas('message_threads', ['id'=>$thread, 'sai_term_id'=>$old->id]);
        $this->assertSame($oldRaw, $old->fresh()->getRawOriginal());
        $this->assertDatabaseHas('property_platform_receivables', ['advertiser_user_id'=>$broker->id, 'amount_total'=>8000]);
    }

    public function test_owner_policy_and_zero_fee_fallback_are_preserved(): void
    {
        [, $ownerHeaders] = $this->actor('owner', 'owner');
        $id = $this->createListing($ownerHeaders);
        $this->withHeaders($ownerHeaders)->putJson("/api/properties/$id/sai",
            ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>30000])->assertUnprocessable();
        $this->withHeaders($ownerHeaders)->putJson("/api/properties/$id/sai", [])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 20);
        [, $brokerHeaders] = $this->actor('zero');
        $otherId = $this->createListing($brokerHeaders);
        $this->withHeaders($brokerHeaders)->putJson("/api/properties/$otherId/sai",
            ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>0])->assertOk()
            ->assertJsonPath('data.sai.amount_type', 'percentage')
            ->assertJsonPath('data.sai.rate_percent', 20)
            ->assertJsonPath('data.sai_management.source_mode', 'platform_fallback')
            ->assertJsonPath('data.sai.fixed_amount', null);
    }

    public function test_fixed_term_fields_are_immutable_too(): void
    {
        [, $headers] = $this->actor('immutable');
        $id = $this->createListing($headers);
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai",
            ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>30000, 'defer_platform_terms'=>true])->assertOk();
        $this->expectException(QueryException::class);
        DB::table('property_sai_terms')->where('property_id', $id)->update(['fixed_sai_amount'=>1]);
    }

    public function test_sale_and_office_fixed_amounts_keep_the_existing_percentage_ceilings(): void
    {
        foreach ([
            ['broker', 'sale', 10000000, 500000],
            ['office', 'rent', 100000, 100000],
        ] as [$type, $purpose, $basis, $maximum]) {
            [, $headers] = $this->actor($type.'-'.$purpose, $type);
            $id = $this->createListing($headers, ['purpose'=>$purpose, 'price'=>$basis,
                'monthly_rent'=>$purpose === 'rent' ? $basis : null,
                'tenure_type'=>$purpose === 'sale' ? 'freehold' : null,
                'area_value'=>140, 'area_unit'=>'sqm', 'unit_number'=>$type.'-'.$purpose]);
            $input = ['sai_amount_type'=>'fixed', 'fixed_sai_amount'=>$maximum, 'defer_platform_terms'=>true];
            $this->withHeaders($headers)->putJson("/api/properties/$id/sai", $input)->assertOk()
                ->assertJsonPath('data.sai.fixed_amount', $maximum);
            $this->withHeaders($headers)->putJson("/api/properties/$id/sai",
                array_merge($input, ['fixed_sai_amount'=>$maximum + 0.01]))->assertUnprocessable();
        }
    }

    public function test_unspecified_rental_units_are_not_merged_and_still_require_support_identity_review(): void
    {
        [$broker, $headers] = $this->actor('optional-position');
        $this->withHeaders($headers)->post('/api/properties', $this->payload(['unit_number'=>'', 'floor_number'=>'']))
            ->assertUnprocessable()->assertJsonValidationErrors('floor_number');
        $id = $this->createListing($headers, ['unit_number'=>'']);
        $property = Property::findOrFail($id);
        $assetId = $property->property_asset_id;
        $this->assertNull($property->area_value);
        $this->assertNull($property->has_elevator);
        $this->assertNull($property->propertyAsset->unit_identity_key);
        $otherId = $this->createListing($headers, ['unit_number'=>'']);
        $this->assertNotSame($assetId, Property::findOrFail($otherId)->property_asset_id);
        $this->withHeaders($headers)->postJson("/api/properties/$id", ['description'=>'وصف معدل من حقائق العقار'])->assertOk();
        $this->assertSame($assetId, Property::findOrFail($id)->property_asset_id);
        $this->withHeaders($headers)->putJson("/api/properties/$id/sai", ['broker_sai_rate_percent'=>20, 'defer_platform_terms'=>true])->assertOk();
        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")->assertOk();
        $this->assertDatabaseHas('properties', ['id'=>$id, 'duplicate_check_status'=>'needs_support', 'review_status'=>'submitted']);
        $this->assertNull(Property::findOrFail($id)->duplicate_self_verification);
        try {
            app(PropertyIdentityService::class)->assertApprovalAllowed($broker, Property::findOrFail($id));
            $this->fail('An unresolved unit must require an auditable support identity decision.');
        } catch (ValidationException $error) {
            $this->assertArrayHasKey('duplicate_review_reason', $error->errors());
        }
        $result = app(PropertyIdentityService::class)->assertApprovalAllowed($broker, Property::findOrFail($id), 'تمت مراجعة موضع الوحدة والعقار والمستندات بصورة مستقلة');
        $this->assertSame('possible_duplicate', $result['decision']);
    }

    private function publish(int $id): void
    {
        Property::findOrFail($id)->forceFill(['status'=>'published', 'review_status'=>'approved', 'published_at'=>now()])->save();
    }

    private function actor(string $key, ?string $type = 'broker'): array
    {
        $user = User::create(['name'=>'أحمد محمد علي صالح', 'email'=>$key.'@wave5.example.test',
            'phone'=>'+96777'.substr(hash('sha256', $key), 0, 10), 'password'=>Hash::make('fixture-'.$key),
            'phone_verified_at'=>now(), 'profile_completed_at'=>now(), 'identity_policy_version'=>2, 'account_status'=>'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        if ($type) AccountVerificationProfile::create(['user_id'=>$user->id, 'type'=>$type, 'status'=>'approved',
            'submitted_at'=>now()->subDay(), 'reviewed_at'=>now()]);
        $token = 'wave5_'.hash('sha256', $key);
        $user->apiTokens()->create(['name'=>'wave5-test', 'token_hash'=>hash('sha256', $token),
            'token_prefix'=>substr($token, 0, 12), 'expires_at'=>now()->addHour()]);
        return [$user->fresh(), ['Authorization'=>'Bearer '.$token, 'Accept'=>'application/json']];
    }

    private function createListing(array $headers, array $changes = []): int
    {
        return (int) $this->withHeaders($headers)->post('/api/properties', $this->payload($changes))->assertCreated()->json('data.id');
    }

    private function payload(array $changes = []): array
    {
        return array_merge(['listing_input_version'=>7, 'title'=>'شقة إيجار في حدة', 'description'=>'ثلاث غرف في الدور الثاني.',
            'purpose'=>'rent', 'type'=>'apartment', 'price'=>100000, 'monthly_rent'=>100000, 'currency'=>'YER',
            'area_value'=>null, 'area_unit'=>null, 'bedrooms'=>3, 'bathrooms'=>2, 'floor_number'=>'2', 'unit_number'=>'شمالية',
            'has_parking'=>0, 'building_facade'=>'north', 'address'=>'صنعاء حدة شارع 14', 'latitude'=>15.3694, 'longitude'=>44.191,
            'images'=>[UploadedFile::fake()->image('listing.jpg')]], $changes);
    }
}
