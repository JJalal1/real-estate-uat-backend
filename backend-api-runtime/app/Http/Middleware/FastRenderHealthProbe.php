<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class FastRenderHealthProbe
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->is('api/health') && str_starts_with((string) $request->userAgent(), 'Render/')) {
            return response()->json([
                'status' => 'ok',
                'liveness' => true,
            ]);
        }

        return $next($request);
    }
}
