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
        $metrics = null;
        if (app()->environment('staging', 'uat', 'testing') && $request->header('X-Aqer-Diagnostics') === 'perf-109') {
            $metrics = new \App\Services\RequestPerformance;
            $request->attributes->set(\App\Services\RequestPerformance::ATTRIBUTE, $metrics);
        }

        /** @var Response $response */
        $response = $next($request);
        $response->headers->set('X-Request-ID', $requestId);
        if ($metrics !== null) {
            $appMs = (hrtime(true) - $startedAt) / 1_000_000;
            // PHP entry to middleware completion; excludes Render wake-up,
            // reverse-proxy/Apache queueing, TLS and response-body transfer.
            $phpMs = defined('LARAVEL_START') ? (microtime(true) - LARAVEL_START) * 1000 : $appMs;
            $response->headers->set('Server-Timing', sprintf('app;dur=%.1f, db;dur=%.1f, storage;dur=%.1f, php;dur=%.1f',
                $appMs, $metrics->databaseMs, $metrics->storageMs, $phpMs));
            $response->headers->set('X-Aqer-DB-Queries', (string) $metrics->queries);
            $response->headers->set('X-Aqer-Storage-Requests', (string) $metrics->storageRequests);
            // These diagnostics are deliberately opt-in and UAT-only.
            $response->headers->set('Cache-Control', 'private, no-store');
        }

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
