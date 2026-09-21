<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use App\Services\PropertySaiSettlementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PropertySaiAgreementSettlementTest extends TestCase
{
    use RefreshDatabase;

    public function test_sale_settlement_uses_final_agreed_amount_frozen_thread_term_and_is_idempotent(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user('sai-settle-owner@example.test', '+967771000001');
        [, $buyerHeaders] = $this->user('sai-settle-buyer@example.test', '+967771000002');
        $property = $this->property($advertiser, 'sale', 100_000_000, 'Sai settlement sale');

        $frozenTerm = $this->term($property, 1, 'broker_custom', 5, 'buyer', 20, 80);
        $property->forceFill(['current_sai_term_id' => $frozenTerm->id])->save();

        $threadId = (int) $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        // A later listing-policy version must not alter the already-started
        // customer's transaction journey.
        $laterTerm = $this->term($property, 2, 'owner_fixed', 1, 'seller', 100, 0);
        $property->forceFill(['current_sai_term_id' => $laterTerm->id])->save();

        $created = $this->withHeaders($buyerHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount' => 90_000_000,
                'currency' => 'YER',
            ])->assertCreated();
        $agreementId = (int) $created->json('data.id');
        $revisionId = (int) $created->json('data.current_revision.id');

        $this->withHeaders($buyerHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()->assertJsonPath('data.status', 'draft');
        $this->assertDatabaseCount('property_sai_settlements', 0);

        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()->assertJsonPath('data.status', 'accepted');

        $this->assertDatabaseHas('property_sai_settlements', [
            'property_agreement_id' => $agreementId,
            'property_agreement_revision_id' => $revisionId,
            'property_id' => $property->id,
            'sai_term_id' => $frozenTerm->id,
            'transaction_type' => 'sale',
            'payer' => 'buyer',
            'calculation_basis' => 'final_sale_value',
            'basis_amount' => 90_000_000,
            'currency' => 'YER',
            'sai_rate_percent' => 5,
            'total_sai_amount' => 4_500_000,
            'platform_share_percent' => 20,
            'platform_share_amount' => 900_000,
            'broker_share_percent' => 80,
            'broker_share_amount' => 3_600_000,
        ]);

        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk();
        $this->assertDatabaseCount('property_sai_settlements', 1);
    }

    public function test_annual_rent_settlement_uses_one_month_equivalent_not_full_period(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user('sai-settle-landlord@example.test', '+967771000003');
        [, $tenantHeaders] = $this->user('sai-settle-tenant@example.test', '+967771000004');
        $property = $this->property($advertiser, 'rent', 100_000, 'Sai settlement rent');
        $term = $this->term($property, 1, 'owner_fixed', 20, 'tenant', 100, 0);
        $property->forceFill(['current_sai_term_id' => $term->id])->save();

        $threadId = (int) $this->withHeaders($tenantHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()->json('data.id');
        $created = $this->withHeaders($tenantHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount' => 1_200_000,
                'currency' => 'YER',
                'rent_cadence' => 'annual',
                'rental_start_date' => now()->addMonth()->toDateString(),
                'rental_end_date' => now()->addMonths(13)->toDateString(),
            ])->assertCreated();
        $agreementId = (int) $created->json('data.id');
        $revisionId = (int) $created->json('data.current_revision.id');

        $this->withHeaders($tenantHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])->assertOk();
        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()->assertJsonPath('data.status', 'accepted');

        $this->assertDatabaseHas('property_sai_settlements', [
            'property_agreement_id' => $agreementId,
            'sai_term_id' => $term->id,
            'transaction_type' => 'rent',
            'calculation_basis' => 'first_month_rent',
            'basis_amount' => 100_000,
            'sai_rate_percent' => 20,
            'total_sai_amount' => 20_000,
            'platform_share_amount' => 20_000,
            'broker_share_amount' => 0,
        ]);
    }

    public function test_rent_cadence_normalization_is_explicit_for_all_supported_cadences(): void
    {
        $service = app(PropertySaiSettlementService::class);
        $this->assertSame(120_000.0, $service->basisAmount('rent', 120_000, 'monthly'));
        $this->assertSame(120_000.0, $service->basisAmount('rent', 360_000, 'quarterly'));
        $this->assertSame(120_000.0, $service->basisAmount('rent', 720_000, 'semiannual'));
        $this->assertSame(120_000.0, $service->basisAmount('rent', 1_440_000, 'annual'));
        $this->assertSame(95_000_000.0, $service->basisAmount('sale', 95_000_000, null));
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Sai Settlement User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make(uniqid('sai-settlement-fixture-', true)),
        ]);
        $role = Role::query()->where('key', 'registered_user')->firstOrFail();
        $user->roles()->sync([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
        $plain = 'saisettle_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'sai-settlement-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }

    private function property(User $advertiser, string $purpose, float $price, string $title): Property
    {
        $asset = PropertyAsset::query()->create([
            'created_by_user_id' => $advertiser->id,
            'identity_hash' => hash('sha256', $title.uniqid('', true)),
            'identity_version' => 1,
            'property_type' => 'apartment',
            'canonical_address' => 'Sai settlement address',
            'canonical_latitude' => 15.3694,
            'canonical_longitude' => 44.1910,
            'area_m2' => 120,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'status' => 'active',
        ]);

        return Property::query()->create([
            'user_id' => $advertiser->id,
            'property_asset_id' => $asset->id,
            'title' => $title,
            'description' => 'Sai settlement integration fixture',
            'purpose' => $purpose,
            'type' => 'apartment',
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => 120,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'Sai settlement address',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'published_at' => now(),
        ]);
    }

    private function term(
        Property $property,
        int $version,
        string $sourceMode,
        float $rate,
        string $payer,
        float $platformShare,
        float $brokerShare,
    ): PropertySaiTerm {
        return PropertySaiTerm::query()->create([
            'property_id' => $property->id,
            'version' => $version,
            'advertiser_type' => $sourceMode === 'broker_custom' ? 'broker' : 'owner',
            'purpose' => $property->purpose,
            'source_mode' => $sourceMode,
            'requested_broker_rate_percent' => $sourceMode === 'broker_custom' ? $rate : null,
            'sai_rate_percent' => $rate,
            'payer' => $payer,
            'calculation_basis' => $property->purpose === 'sale' ? 'final_sale_value' : 'first_month_rent',
            'platform_share_percent' => $platformShare,
            'broker_share_percent' => $brokerShare,
            'platform_terms_status' => $sourceMode === 'broker_custom' ? 'accepted' : 'not_required',
            'platform_terms_accepted_at' => $sourceMode === 'broker_custom' ? now() : null,
            'platform_terms_rejected_at' => null,
            'created_by_user_id' => $property->user_id,
        ]);
    }
}
