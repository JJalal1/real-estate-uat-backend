<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

class GoogleMapAddressSearch
{
    /** @return list<array{label: string, latitude: float, longitude: float, partial: bool}>|null */
    public function find(string $address): ?array
    {
        $key = trim((string) config('geocoding.google_address_search.key'));
        if (! config('geocoding.enabled') || ! config('geocoding.google_address_search.enabled') || $key === '') {
            return null;
        }

        try {
            $store = (string) config('geocoding.cache_store');
            $driver = config('cache.stores.'.$store.'.driver');
            if (! in_array($driver, ['database', 'redis', 'memcached'], true) && ! app()->environment('testing')) {
                return null;
            }
            $counter = Cache::store($store);
            if (! $counter->add('geocoding:google-address:burst', true, 1)) {
                return null;
            }
            $today = now('UTC');
            $daily = 'geocoding:google-address:'.$today->toDateString();
            $counter->add($daily, 0, $today->copy()->addDay()->startOfDay());
            $count = $counter->increment($daily);
            if (! is_int($count) || $count > (int) config('geocoding.google_address_search.daily_limit')) {
                return null;
            }

            // Only the address submitted by the user leaves the API.
            // Provider results are forwarded for temporary display and never cached.
            $reply = Http::acceptJson()->withOptions(['allow_redirects' => false])
                ->connectTimeout(2)->timeout(5)
                ->get('https://maps.googleapis.com/maps/api/geocode/json', [
                    'address' => $address, 'components' => 'country:YE',
                    'language' => 'ar', 'region' => 'ye', 'key' => $key,
                ]);
            if (! $reply->successful() || strlen($reply->body()) > 150000) {
                return null;
            }
            return match ($reply->json('status')) {
                'OK' => $this->matches($reply->json('results')),
                'ZERO_RESULTS' => [],
                default => null,
            };
        } catch (\Throwable) {
            return null;
        }
    }

    private function matches(mixed $results): ?array
    {
        if (! is_array($results)) {
            return null;
        }
        $matches = [];
        foreach ($results as $result) {
            if (! is_array($result) || ! $this->isInYemen($result)) {
                continue;
            }
            $label = $result['formatted_address'] ?? null;
            $point = $result['geometry']['location'] ?? [];
            $lat = $point['lat'] ?? null;
            $lon = $point['lng'] ?? null;
            if (! is_string($label) || trim($label) === '' || mb_strlen($label) > 240 ||
                ! is_numeric($lat) || ! is_numeric($lon) ||
                ! is_finite((float) $lat) || ! is_finite((float) $lon) ||
                abs((float) $lat) > 90 || abs((float) $lon) > 180 ||
                ((float) $lat === 0.0 && (float) $lon === 0.0)) {
                continue;
            }
            $matches[] = ['label' => trim($label), 'latitude' => (float) $lat,
                'longitude' => (float) $lon, 'partial' => ($result['partial_match'] ?? null) === true];
            if (count($matches) === 8) {
                break;
            }
        }
        return $matches;
    }

    private function isInYemen(array $result): bool
    {
        $components = $result['address_components'] ?? null;
        if (! is_array($components)) {
            return false;
        }
        foreach ($components as $component) {
            if (is_array($component) && is_array($component['types'] ?? null) &&
                in_array('country', $component['types'], true)) {
                return ($component['short_name'] ?? null) === 'YE';
            }
        }
        return false;
    }
}
