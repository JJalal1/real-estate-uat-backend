<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class RequestObservability
{
    public function handle(Request $request, Closure $next): Response
    {
        $startedAt = hrtime(true);
        $requestId = (string) Str::uuid();
        $request->attributes->set('request_id', $requestId);

        /** @var Response $response */
        $response = $next($request);
        $response->headers->set('X-Request-ID', $requestId);

        if ($request->is('api/health') || $request->is('up')) {
            return $response;
        }

        $durationMs = round((hrtime(true) - $startedAt) / 1_000_000, 1);
        $status = $response->getStatusCode();
        $slowThresholdMs = max(250, (int) env('OBSERVABILITY_SLOW_REQUEST_MS', 1500));

        if ($status >= 500 || $durationMs >= $slowThresholdMs) {
            $context = [
                'request_id' => $requestId,
                'method' => $request->getMethod(),
                'path' => '/'.$request->path(),
                'status' => $status,
                'duration_ms' => $durationMs,
            ];

            if ($status >= 500) {
                Log::error('api_request_failed', $context);
            } else {
                Log::warning('api_request_slow', $context);
            }
        }

        return $response;
    }
}
