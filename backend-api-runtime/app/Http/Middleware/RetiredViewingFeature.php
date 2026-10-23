<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Retire the old workflow without deleting historical bookings or messages. */
class RetiredViewingFeature
{
    public function handle(Request $request, Closure $next): JsonResponse
    {
        return response()->json(['message' => 'نسّق زيارة العقار مباشرة في المحادثة مع المعلن.',
            'code' => 'viewings_retired'], 410);
    }
}
