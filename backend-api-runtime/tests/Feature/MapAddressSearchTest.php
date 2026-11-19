<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MapAddressSearchTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config([
            'geocoding.enabled' => true,
            'geocoding.cache_store' => 'array',
            'geocoding.google_address_search.enabled' => true,
            'geocoding.google_address_search.key' => 'synthetic-test-key',
            'geocoding.google_address_search.daily_limit' => 5,
        ]);
        Http::preventStrayRequests();
    }

    public function test_unconfigured_search_uses_no_provider_and_cannot_cache_its_response(): void
    {
        config(['geocoding.google_address_search.enabled' => false]);
        Http::fake();
        $response = $this->postJson('/api/marketplace/address-search', ['address' => 'حدة']);
        $response->assertOk()->assertExactJson(['available' => false, 'data' => []]);
        self::assertStringContainsString('no-store', $response->headers->get('cache-control'));
        Http::assertNothingSent();
    }

    public function test_yemen_only_address_matches_keep_approximation_markers(): void
    {
        Http::fake(['maps.googleapis.com/*' => Http::response([
            'status' => 'OK',
            'results' => [
                $this->geocodeResult('حدة، صنعاء', 'YE', 15.31, 44.19, true),
                $this->geocodeResult('خارج اليمن', 'SA', 21.4, 39.8, false),
                $this->geocodeResult('إحداثيات غير صالحة', 'YE', 100, 44.2, false),
            ],
        ])]);

        $this->postJson('/api/marketplace/address-search', ['address' => 'حدة'])
            ->assertOk()->assertExactJson(['available' => true, 'data' => [[
                'label' => 'حدة، صنعاء', 'latitude' => 15.31, 'longitude' => 44.19, 'partial' => true,
            ]]]);

        Http::assertSent(function (Request $request): bool {
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);
            return $request->method() === 'GET' && $query === [
                'address' => 'حدة', 'components' => 'country:YE', 'language' => 'ar',
                'region' => 'ye', 'key' => 'synthetic-test-key',
            ];
        });
    }

    public function test_daily_limit_counts_upstream_attempts_and_results_are_not_reused(): void
    {
        config(['geocoding.google_address_search.daily_limit' => 2]);
        Http::fakeSequence('maps.googleapis.com/*')
            ->push(['status' => 'ZERO_RESULTS'])
            ->push(['status' => 'REQUEST_DENIED', 'error_message' => 'provider credentials']);

        $search = ['address' => 'الروضة'];
        $this->postJson('/api/marketplace/address-search', $search)
            ->assertOk()->assertExactJson(['available' => true, 'data' => []]);
        $this->travel(2)->seconds();
        $this->postJson('/api/marketplace/address-search', $search)
            ->assertOk()->assertExactJson(['available' => false, 'data' => []]);
        $this->travel(2)->seconds();
        $this->postJson('/api/marketplace/address-search', $search)
            ->assertOk()->assertExactJson(['available' => false, 'data' => []]);
        Http::assertSentCount(2);
    }

    private function geocodeResult(string $label, string $country, float $lat, float $lon, bool $partial): array
    {
        return [
            'formatted_address' => $label,
            'address_components' => [['types' => ['country'], 'short_name' => $country]],
            'geometry' => ['location' => ['lat' => $lat, 'lng' => $lon]],
            'partial_match' => $partial,
        ];
    }
}
