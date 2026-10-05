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

    public function test_historical_financial_hold_does_not_hide_a_published_listing_or_mutate_finance(): void
    {
        [$advertiser] = $this->user('held-advertiser@example.test', '+967772100002');
        $property = $this->property($advertiser, 'Published despite historical finance');
        $property->forceFill([
            'financial_hold_at' => now()->subDay(),
            'financial_hold_reason' => 'historical_only',
        ])->saveQuietly();

        $before = $this->financeCounts();

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
