<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\AgreementContractController;
use App\Http\Controllers\Api\PropertyController;
use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class FinancialV1ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_financial_and_paid_service_routes_are_not_exposed_in_free_core(): void
    {
        [, $headers] = $this->user('finance-disabled@example.test', '+967772100001');

        foreach ([
            ['GET', '/api/finance/payments/mine'],
            ['GET', '/api/finance/account'],
            ['GET', '/api/admin/finance/summary'],
            ['GET', '/api/admin/finance/workspace'],
            ['POST', '/api/finance/agreements/999/payments'],
            ['POST', '/api/finance/agreements/999/direct-confirmation'],
            ['POST', '/api/finance/receivables/999/payments'],
            ['POST', '/api/properties/999/sai-attestation'],
            ['GET', '/api/services/catalog'],
            ['POST', '/api/services/orders'],
            ['POST', '/api/admin/payments/orders/999/settle'],
            ['POST', '/api/admin/payments/orders/999/refund'],
        ] as [$method, $uri]) {
            $response = match ($method) {
                'POST' => $this->withHeaders($headers)->postJson($uri, []),
                default => $this->withHeaders($headers)->getJson($uri),
            };

            $response->assertNotFound();
        }
    }

    public function test_core_routes_resolve_to_non_financial_controllers(): void
    {
        $routes = collect(app('router')->getRoutes()->getRoutes());

        $propertyIndex = $routes->first(
            fn ($route) => in_array('GET', $route->methods(), true)
                && $route->uri() === 'api/properties',
        );
        $this->assertNotNull($propertyIndex);
        $this->assertStringContainsString(PropertyController::class.'@index', $propertyIndex->getActionName());

        $agreementMine = $routes->first(
            fn ($route) => in_array('GET', $route->methods(), true)
                && $route->uri() === 'api/agreements/mine',
        );
        $this->assertNotNull($agreementMine);
        $this->assertStringContainsString(AgreementContractController::class.'@agreementsMine', $agreementMine->getActionName());

        $this->assertSame(
            0,
            $routes->filter(fn ($route) => str_contains($route->getActionName(), 'FinancialPropertyController'))->count(),
        );
        $this->assertSame(
            0,
            $routes->filter(fn ($route) => str_contains($route->getActionName(), 'FinancialAgreementContractController'))->count(),
        );
    }

    public function test_historical_overdue_receivable_does_not_hide_public_listing_or_mutate_finance(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user(
            'held-advertiser@example.test',
            '+967772100002',
        );
        [$buyer, $buyerHeaders] = $this->user(
            'historical-buyer@example.test',
            '+967772100003',
        );
        $property = $this->property($advertiser, 'Published despite historical finance');
        $property->forceFill([
            'financial_hold_at' => now()->subDay(),
            'financial_hold_reason' => 'historical_only',
        ])->saveQuietly();

        $threadId = (int) $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()
            ->json('data.id');

        $agreement = $this->withHeaders($buyerHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount' => 24_000_000,
                'currency' => 'YER',
            ])
            ->assertCreated();

        $agreementId = (int) $agreement->json('data.id');
        $revisionId = (int) $agreement->json('data.current_revision.id');

        $termId = (int) DB::table('property_deal_financial_terms')->insertGetId([
            'property_agreement_id' => $agreementId,
            'property_agreement_revision_id' => $revisionId,
            'property_sai_settlement_id' => null,
            'property_id' => $property->id,
            'buyer_user_id' => $buyer->id,
            'advertiser_user_id' => $advertiser->id,
            'transaction_type' => 'sale',
            'advertiser_type' => 'owner',
            'currency' => 'YER',
            'base_amount' => 24_000_000,
            'monthly_basis_amount' => null,
            'rental_term_months' => null,
            'advance_months' => null,
            'sai_payer' => 'seller',
            'sai_total_amount' => 240_000,
            'platform_share_amount' => 240_000,
            'advertiser_sai_share_amount' => 0,
            'price_display_mode' => null,
            'snapshot' => json_encode(['historical_fixture' => true]),
            'frozen_at' => now()->subDays(2),
            'created_at' => now()->subDays(2),
            'updated_at' => now()->subDays(2),
        ]);

        $receivableId = (int) DB::table('property_platform_receivables')->insertGetId([
            'reference' => 'HIST-W4B-0001',
            'deal_financial_term_id' => $termId,
            'property_id' => $property->id,
            'advertiser_user_id' => $advertiser->id,
            'amount_total' => 240_000,
            'amount_paid' => 0,
            'currency' => 'YER',
            'status' => 'overdue',
            'confirmed_direct_at' => now()->subDays(2),
            'due_at' => now()->subDay(),
            'paid_at' => null,
            'created_at' => now()->subDays(2),
            'updated_at' => now()->subDays(2),
        ]);

        $this->assertGreaterThan(0, $receivableId);
        $before = $this->financeCounts();

        $this->flushHeaders();
        $this->getJson("/api/properties/{$property->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $property->id)
            ->assertJsonPath('data.status', 'published')
            ->assertJsonMissingPath('data.financial_hold')
            ->assertJsonMissingPath('data.sai');

        $this->getJson('/api/properties')
            ->assertOk()
            ->assertJsonFragment(['id' => $property->id]);

        $this->assertSame($before, $this->financeCounts());
        $this->assertDatabaseHas('property_platform_receivables', [
            'id' => $receivableId,
            'status' => 'overdue',
            'amount_paid' => 0,
        ]);
        $this->assertDatabaseHas('properties', [
            'id' => $property->id,
            'status' => 'published',
            'financial_hold_reason' => 'historical_only',
        ]);
    }

    private function financeCounts(): array
    {
        return [
            'terms' => DB::table('property_deal_financial_terms')->count(),
            'payments' => DB::table('property_payments')->count(),
            'receivables' => DB::table('property_platform_receivables')->count(),
            'holds' => DB::table('property_financial_holds')->count(),
            'settlements' => DB::table('property_sai_settlements')->count(),
        ];
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'W4b Free Core User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('w4b-free-core-password'),
        ]);

        $plain = 'w4b_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'w4b-free-core',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(User $advertiser, string $title): Property
    {
        return Property::query()->create([
            'user_id' => $advertiser->id,
            'title' => $title,
            'description' => 'W4b free-core publication fixture',
            'purpose' => 'sale',
            'type' => 'apartment',
            'price' => 25_000_000,
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
