<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\User;
use App\Services\PropertySaiService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use Tests\TestCase;

class PropertySaiPolicyAcceptanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_ordinary_advertiser_sets_sale_sai_before_enrolling_and_platform_uses_broker_share(): void
    {
        [$owner, $headers] = $this->user('ordinary-sale');
        $property = $this->property($owner, 'sale', 100_000_000);

        $this->withHeaders($headers)->getJson('/api/listing-sai-policy?purpose=sale')
            ->assertOk()
            ->assertJsonPath('data.advertiser_type', 'broker')
            ->assertJsonPath('data.amount_types', ['percentage', 'fixed']);
        $this->withHeaders($headers)->getJson('/api/broker/workspace')->assertForbidden();
        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'broker_sai_rate_percent' => 3.25,
        ])->assertUnprocessable()->assertJsonValidationErrors('platform_terms_decision');

        $response = $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 3.25,
            'platform_terms_decision' => 'accept',
        ])->assertOk();

        $response
            ->assertJsonPath('data.sai.rate_percent', 3.25)
            ->assertJsonPath('data.sai.payer', 'buyer')
            ->assertJsonPath('data.sai.calculation_basis', 'final_sale_value')
            ->assertJsonPath('data.sai_management.advertiser_type', 'broker')
            ->assertJsonPath('data.sai_management.platform_share_percent', 20)
            ->assertJsonPath('data.sai_management.broker_share_percent', 80);

        [, $buyerHeaders] = $this->user('ordinary-sale-buyer');
        $property->forceFill([
            'status' => 'published', 'review_status' => 'approved', 'published_at' => now(),
        ])->save();
        $threadId = $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")->assertCreated()->json('data.id');
        $dealId = $this->withHeaders($headers)->postJson("/api/broker/customers/$threadId/completed-deal", [
            'basis_amount' => 80_000_000,
        ])->assertCreated()->assertJsonPath('data.status', 'confirmed')->json('data.id');
        $this->assertDatabaseHas('property_deal_financial_terms', [
            'broker_deal_outcome_id' => $dealId,
            'advertiser_user_id' => $owner->id,
            'sai_total_amount' => 2_600_000,
            'platform_share_amount' => 520_000,
            'advertiser_sai_share_amount' => 2_080_000,
        ]);
        $this->assertNull($owner->fresh()->broker_enrolled_at);
    }

    public function test_legacy_owner_can_set_a_fixed_rent_fee_with_the_same_broker_share(): void
    {
        [$owner, $headers] = $this->advertiser('owner', 'owner-rent');
        $property = $this->property($owner, 'rent', 100_000);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
            'sai_amount_type' => 'fixed',
            'fixed_sai_amount' => 30_000,
            'platform_terms_decision' => 'accept',
        ])->assertOk()
            ->assertJsonPath('data.sai.amount_type', 'fixed')
            ->assertJsonPath('data.sai.fixed_amount', 30_000)
            ->assertJsonPath('data.sai.calculation_basis', 'first_month_rent');

        $term = PropertySaiTerm::query()->findOrFail($property->fresh()->current_sai_term_id);
        $amounts = app(PropertySaiService::class)->calculateSaiAmount($term, 100_000);
        $this->assertSame(30_000.0, $amounts['total_sai']);
        $this->assertSame(6_000.0, $amounts['platform_share']);
        $this->assertSame(24_000.0, $amounts['broker_share']);
    }

    public function test_broker_sale_five_percent_is_total_sai_and_platform_gets_twenty_percent_inside_it(): void
    {
        [$broker, $headers] = $this->advertiser('broker', 'broker-sale');
        $property = $this->property($broker, 'sale', 100_000_000);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 5,
        ])->assertUnprocessable();

        $accepted = $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 5,
            'platform_terms_decision' => 'accept',
        ])->assertOk();

        $accepted
            ->assertJsonPath('data.sai.rate_percent', 5)
            ->assertJsonPath('data.sai.display_text', 'السعي 5% - يتحملها المشتري')
            ->assertJsonPath('data.sai_management.platform_share_percent', 20)
            ->assertJsonPath('data.sai_management.broker_share_percent', 80)
            ->assertJsonPath('data.sai_management.platform_terms_status', 'accepted')
            ->assertJsonPath('data.sai_management.platform_terms_message', 'للتطبيق نسبة مقدارها 20% من مبلغ السعي عند إتمام الصفقة.');

        $term = PropertySaiTerm::query()->findOrFail($property->fresh()->current_sai_term_id);
        $amounts = app(PropertySaiService::class)->calculateSaiAmount($term, 100_000_000);
        $this->assertSame(5_000_000.0, $amounts['total_sai']);
        $this->assertSame(1_000_000.0, $amounts['platform_share']);
        $this->assertSame(4_000_000.0, $amounts['broker_share']);
    }

    public function test_office_rent_hundred_percent_is_capped_to_one_month_and_internal_split_is_twenty_eighty(): void
    {
        [$office, $headers] = $this->advertiser('office', 'office-rent');
        $property = $this->property($office, 'rent', 100_000);

        $response = $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
            'broker_sai_rate_percent' => 100,
            'platform_terms_decision' => 'accept',
        ])->assertOk();

        $response
            ->assertJsonPath('data.sai.rate_percent', 100)
            ->assertJsonPath('data.sai.calculation_basis', 'first_month_rent')
            ->assertJsonPath('data.sai.display_text', 'السعي 100% - يتحملها المستأجر')
            ->assertJsonPath('data.sai_management.platform_share_percent', 20)
            ->assertJsonPath('data.sai_management.broker_share_percent', 80);

        $term = PropertySaiTerm::query()->findOrFail($property->fresh()->current_sai_term_id);
        $amounts = app(PropertySaiService::class)->calculateSaiAmount($term, 100_000);
        $this->assertSame(100_000.0, $amounts['total_sai']);
        $this->assertSame(20_000.0, $amounts['platform_share']);
        $this->assertSame(80_000.0, $amounts['broker_share']);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
            'broker_sai_rate_percent' => 100.01,
            'platform_terms_decision' => 'accept',
        ])->assertUnprocessable();
    }

    public function test_broker_zero_percent_activates_fixed_platform_sai_instead_of_zero(): void
    {
        [$broker, $saleHeaders] = $this->advertiser('broker', 'broker-zero-sale');
        $sale = $this->property($broker, 'sale', 80_000_000);

        $this->withHeaders($saleHeaders)->putJson("/api/properties/{$sale->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 0,
        ])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 1)
            ->assertJsonPath('data.sai.display_text', 'السعي 1% - يتحملها المشتري')
            ->assertJsonPath('data.sai_management.source_mode', 'platform_fallback')
            ->assertJsonPath('data.sai_management.platform_share_percent', 100)
            ->assertJsonPath('data.sai_management.broker_share_percent', 0)
            ->assertJsonPath('data.sai_management.platform_terms_status', 'not_required');

        [$office, $rentHeaders] = $this->advertiser('office', 'office-zero-rent');
        $rent = $this->property($office, 'rent', 150_000);

        $this->withHeaders($rentHeaders)->putJson("/api/properties/{$rent->id}/sai", [
            'sai_payer' => 'tenant',
            'broker_sai_rate_percent' => 0,
        ])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 20)
            ->assertJsonPath('data.sai.display_text', 'السعي 20% - يتحملها المستأجر')
            ->assertJsonPath('data.sai_management.source_mode', 'platform_fallback')
            ->assertJsonPath('data.sai_management.platform_share_percent', 100)
            ->assertJsonPath('data.sai_management.broker_share_percent', 0);
    }

    public function test_sale_broker_rate_cannot_exceed_five_percent_and_payer_must_match_purpose(): void
    {
        [$broker, $headers] = $this->advertiser('broker', 'broker-limits');
        $property = $this->property($broker, 'sale', 100_000_000);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 5.01,
            'platform_terms_decision' => 'accept',
        ])->assertUnprocessable();

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
            'broker_sai_rate_percent' => 2,
            'platform_terms_decision' => 'accept',
        ])->assertUnprocessable();
    }

    public function test_rejected_broker_terms_block_submission_state_transition(): void
    {
        [$broker, $headers] = $this->advertiser('broker', 'broker-reject');
        $property = $this->property($broker, 'sale', 100_000_000);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 3,
            'platform_terms_decision' => 'reject',
        ])->assertOk()
            ->assertJsonPath('data.sai_management.platform_terms_status', 'rejected');

        try {
            $property->forceFill(['status' => 'pending', 'review_status' => 'submitted'])->save();
            $this->fail('Rejected broker sai terms must block submission.');
        } catch (ConflictHttpException $exception) {
            $this->assertStringContainsString('يجب قبول شرط نسبة التطبيق', $exception->getMessage());
        }
    }

    public function test_public_sai_endpoint_never_exposes_platform_or_broker_internal_split(): void
    {
        [$broker, $headers] = $this->advertiser('broker', 'broker-public');
        $property = $this->property($broker, 'sale', 100_000_000);
        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 5,
            'platform_terms_decision' => 'accept',
        ])->assertOk();

        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $public = $this->getJson("/api/properties/{$property->id}/sai")->assertOk()
            ->assertJsonPath('data.sai.display_text', 'السعي 5% - يتحملها المشتري');

        $payload = json_encode($public->json(), JSON_UNESCAPED_UNICODE);
        $this->assertStringNotContainsString('platform_share', $payload);
        $this->assertStringNotContainsString('broker_share', $payload);
        $this->assertStringNotContainsString('عمولة المنصة', $payload);
        $this->assertStringNotContainsString('حصة المنصة', $payload);
        $this->assertStringNotContainsString('عمولة الدلال', $payload);
        $this->assertStringNotContainsString('حصة الدلال', $payload);
    }

    public function test_existing_customer_conversation_keeps_old_sai_term_after_later_logged_change(): void
    {
        [$owner, $ownerHeaders] = $this->advertiser('owner', 'owner-versioning');
        [, $buyerOneHeaders] = $this->user('buyer-one');
        [, $buyerTwoHeaders] = $this->user('buyer-two');
        $property = $this->property($owner, 'sale', 100_000_000);

        // Historical seller-paid terms remain attached to historical contacts.
        // New API configurations now always use the customer-paid policy.
        $legacy = PropertySaiTerm::query()->create([
            'property_id' => $property->id, 'version' => 1, 'advertiser_type' => 'owner',
            'purpose' => 'sale', 'source_mode' => 'owner_fixed', 'sai_rate_percent' => 1,
            'payer' => 'seller', 'calculation_basis' => 'final_sale_value',
            'platform_share_percent' => 100, 'broker_share_percent' => 0,
            'platform_terms_status' => 'not_required', 'created_by_user_id' => $owner->id,
        ]);
        $legacyTerms = $legacy->fresh()->getRawOriginal();
        $property->forceFill(['current_sai_term_id' => $legacy->id])->save();
        $termOne = (int) $legacy->id;
        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $threadOne = (int) $this->withHeaders($buyerOneHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');
        $this->assertSame($termOne, (int) MessageThread::query()->findOrFail($threadOne)->sai_term_id);

        $owner->forceFill(['broker_enrolled_at' => now()])->save();
        $property->forceFill(['status' => 'draft', 'review_status' => 'draft', 'published_at' => null])->save();
        $this->withHeaders($ownerHeaders)->putJson("/api/properties/{$property->id}/sai", [])
            ->assertOk()->assertJsonPath('data.sai_management.term_id', $termOne)
            ->assertJsonPath('data.sai.payer', 'seller');
        $this->withHeaders($ownerHeaders)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 2,
            'platform_terms_decision' => 'accept',
        ])->assertOk()->assertJsonPath('data.sai_management.advertiser_type', 'broker');
        $termTwo = (int) $property->fresh()->current_sai_term_id;
        $this->assertNotSame($termOne, $termTwo);
        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $threadTwo = (int) $this->withHeaders($buyerTwoHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        $this->assertSame($termOne, (int) MessageThread::query()->findOrFail($threadOne)->sai_term_id);
        $this->assertSame($termTwo, (int) MessageThread::query()->findOrFail($threadTwo)->sai_term_id);
        $this->assertSame($legacyTerms, $legacy->fresh()->getRawOriginal());
        $this->assertDatabaseCount('property_sai_terms', 2);
    }

    public function test_published_listing_cannot_change_sai_without_returning_to_draft(): void
    {
        [$owner, $headers] = $this->advertiser('owner', 'owner-live-change');
        $property = $this->property($owner, 'rent', 100_000);
        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
        ])->assertOk();
        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
        ])->assertConflict();
    }

    private function advertiser(string $type, string $key): array
    {
        [$user, $headers] = $this->user($key);
        AccountVerificationProfile::query()->create([
            'user_id' => $user->id,
            'type' => $type,
            'status' => AccountVerificationProfile::STATUS_APPROVED,
            'submitted_at' => now()->subHour(),
            'reviewed_at' => now(),
        ]);
        return [$user->fresh(), $headers];
    }

    private function user(string $key): array
    {
        $hash = substr(hash('sha256', $key), 0, 10);
        $user = User::query()->create([
            'name' => 'Sai '.$key,
            'email' => $key.'@sai.example.test',
            'phone' => '+96777'.$hash,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('Sai-fixture-'.$key),
        ]);
        $plain = 'sai_'.substr(hash('sha512', $key), 0, 80);
        $user->apiTokens()->create([
            'name' => 'sai-policy-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(User $advertiser, string $purpose, float $price): Property
    {
        return Property::query()->create([
            'user_id' => $advertiser->id,
            'title' => 'Sai policy property',
            'description' => 'Sai policy acceptance fixture',
            'purpose' => $purpose,
            'type' => 'apartment',
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => 120,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'Sana\'a, Yemen',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'draft',
            'review_status' => 'draft',
        ]);
    }
}
