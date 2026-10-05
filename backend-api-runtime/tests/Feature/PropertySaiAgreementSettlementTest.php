<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PropertySaiAgreementSettlementTest extends TestCase
{
    use RefreshDatabase;

    public function test_accepted_sale_agreement_stays_core_only_without_sai_or_financial_term(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user('w4b-agreement-owner@example.test', '+967772100041');
        [, $buyerHeaders] = $this->user('w4b-agreement-buyer@example.test', '+967772100042');
        $property = $this->property($advertiser, 'sale', 90_000_000, 'W4b free sale');

        $threadId = (int) $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        $created = $this->withHeaders($buyerHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount' => 85_000_000,
                'currency' => 'YER',
            ])
            ->assertCreated();

        $agreementId = (int) $created->json('data.id');
        $revisionId = (int) $created->json('data.current_revision.id');

        $this->withHeaders($buyerHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()
            ->assertJsonPath('data.status', 'draft');

        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()
            ->assertJsonPath('data.status', 'accepted');

        $this->assertDatabaseCount('property_sai_settlements', 0);
        $this->assertDatabaseCount('property_deal_financial_terms', 0);
        $this->assertDatabaseCount('property_platform_receivables', 0);
        $this->assertDatabaseCount('property_financial_holds', 0);
    }

    public function test_accepted_rental_agreement_can_create_core_contract_without_finance(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user('w4b-rent-owner@example.test', '+967772100043');
        [, $tenantHeaders] = $this->user('w4b-rent-tenant@example.test', '+967772100044');
        $property = $this->property($advertiser, 'rent', 250_000, 'W4b free rental');

        $threadId = (int) $this->withHeaders($tenantHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        $created = $this->withHeaders($tenantHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount' => 250_000,
                'currency' => 'YER',
                'rent_cadence' => 'monthly',
                'rental_start_date' => now()->addMonth()->toDateString(),
                'rental_end_date' => now()->addMonths(13)->toDateString(),
            ])
            ->assertCreated();

        $agreementId = (int) $created->json('data.id');
        $revisionId = (int) $created->json('data.current_revision.id');

        $this->withHeaders($tenantHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk();
        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id' => $revisionId])
            ->assertOk()
            ->assertJsonPath('data.status', 'accepted');

        $contract = $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/rental-contract", [
                'rent_amount' => 250_000,
                'currency' => 'YER',
                'rent_cadence' => 'monthly',
                'start_date' => now()->addMonth()->toDateString(),
                'end_date' => now()->addMonths(13)->toDateString(),
                'payment_due_day' => 1,
            ])
            ->assertCreated();

        $this->assertNotNull($contract->json('data.id'));
        $this->assertDatabaseCount('property_sai_settlements', 0);
        $this->assertDatabaseCount('property_deal_financial_terms', 0);
        $this->assertDatabaseCount('property_platform_receivables', 0);
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'W4b Agreement User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('w4b-agreement-password'),
        ]);

        $plain = 'w4bagr_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'w4b-agreement',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(User $advertiser, string $purpose, float $price, string $title): Property
    {
        return Property::query()->create([
            'user_id' => $advertiser->id,
            'title' => $title,
            'description' => 'W4b finance-free agreement fixture',
            'purpose' => $purpose,
            'type' => 'apartment',
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => 120,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'Sanaa',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'published_at' => now(),
        ]);
    }
}
