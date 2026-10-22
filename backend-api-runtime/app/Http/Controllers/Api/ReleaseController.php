<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

class ReleaseController extends Controller
{
    public function show(): JsonResponse
    {
        $android = (array) config('release.android', []);
        $minimum = max(1, (int) ($android['minimum_supported_build'] ?? 1));
        $latest = max($minimum, (int) ($android['latest_build'] ?? $minimum));

        return response()->json([
            'data' => [
                'platform' => 'android',
                'minimum_supported_build' => $minimum,
                'latest_build' => $latest,
                'store_url' => filled($android['store_url'] ?? null)
                    ? (string) $android['store_url']
                    : null,
                'message' => (string) ($android['message'] ?? 'يتوفر إصدار أحدث من عقار.'),
            ],
        ])->header('Cache-Control', 'public, max-age=300');
    }
}
