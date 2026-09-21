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

    public function test_owner_sale_is_fixed_at_one_percent_and_owner_only_selects_payer(): void
    {
        [$owner, $headers] = $this->advertiser('owner', 'owner-sale');
        $property = $this->property($owner, 'sale', 100_000_000);

        $response = $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'seller',
        ])->assertOk();

        $response
            ->assertJsonPath('data.sai.rate_percent', 1)
            ->assertJsonPath('data.sai.payer', 'seller')
            ->assertJsonPath('data.sai.display_text', 'السعي 1% - يتحملها البائع')
            ->assertJsonPath('data.sai.calculation_basis', 'final_sale_value')
            ->assertJsonPath('data.sai_management.advertiser_type', 'owner')
            ->assertJsonPath('data.sai_management.platform_share_percent', 100)
            ->assertJsonPath('data.sai_management.broker_share_percent', 0);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
            'broker_sai_rate_percent' => 1,
        ])->assertUnprocessable();
    }

    public function test_owner_rent_is_fixed_at_twenty_percent_of_first_month_only(): void
    {
        [$owner, $headers] = $this->advertiser('owner', 'owner-rent');
        $property = $this->property($owner, 'rent', 100_000);

        $this->withHeaders($headers)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'tenant',
        ])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 20)
            ->assertJsonPath('data.sai.display_text', 'السعي 20% - يتحملها المستأجر')
            ->assertJsonPath('data.sai.calculation_basis', 'first_month_rent');

        $term = PropertySaiTerm::query()->findOrFail($property->fresh()->current_sai_term_id);
        $amounts = app(PropertySaiService::class)->calculateSaiAmount($term, 100_000);
        $this->assertSame(20_000.0, $amounts['total_sai']);
        $this->assertSame(20_000.0, $amounts['platform_share']);
        $this->assertSame(0.0, $amounts['broker_share']);
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
            'sai_payer' => 'landlord',
            'broker_sai_rate_percent' => 100.01,
            'platform_terms_decision' => 'accept',
        ])->assertUnprocessable();
    }

    public function test_broker_zero_percent_activates_fixed_platform_sai_instead_of_zero(): void
    {
        [$broker, $saleHeaders] = $this->advertiser('broker', 'broker-zero-sale');
        $sale = $this->property($broker, 'sale', 80_000_000);

        $this->withHeaders($saleHeaders)->putJson("/api/properties/{$sale->id}/sai", [
            'sai_payer' => 'seller',
            'broker_sai_rate_percent' => 0,
        ])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 1)
            ->assertJsonPath('data.sai.display_text', 'السعي 1% - يتحملها البائع')
            ->assertJsonPath('data.sai_management.source_mode', 'platform_fallback')
            ->assertJsonPath('data.sai_management.platform_share_percent', 100)
            ->assertJsonPath('data.sai_management.broker_share_percent', 0)
            ->assertJsonPath('data.sai_management.platform_terms_status', 'not_required');

        [$office, $rentHeaders] = $this->advertiser('office', 'office-zero-rent');
        $rent = $this->property($office, 'rent', 150_000);

        $this->withHeaders($rentHeaders)->putJson("/api/properties/{$rent->id}/sai", [
            'sai_payer' => 'landlord',
            'broker_sai_rate_percent' => 0,
        ])->assertOk()
            ->assertJsonPath('data.sai.rate_percent', 20)
            ->assertJsonPath('data.sai.display_text', 'السعي 20% - يتحملها المؤجر')
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

        $this->withHeaders($ownerHeaders)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'seller',
        ])->assertOk();
        $termOne = (int) $property->fresh()->current_sai_term_id;
        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $threadOne = (int) $this->withHeaders($buyerOneHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');
        $this->assertSame($termOne, (int) MessageThread::query()->findOrFail($threadOne)->sai_term_id);

        $property->forceFill(['status' => 'draft', 'review_status' => 'draft', 'published_at' => null])->save();
        $this->withHeaders($ownerHeaders)->putJson("/api/properties/{$property->id}/sai", [
            'sai_payer' => 'buyer',
        ])->assertOk();
        $termTwo = (int) $property->fresh()->current_sai_term_id;
        $this->assertNotSame($termOne, $termTwo);
        $property->forceFill(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()])->save();

        $threadTwo = (int) $this->withHeaders($buyerTwoHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        $this->assertSame($termOne, (int) MessageThread::query()->findOrFail($threadOne)->sai_term_id);
        $this->assertSame($termTwo, (int) MessageThread::query()->findOrFail($threadTwo)->sai_term_id);
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
            'sai_payer' => 'landlord',
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
