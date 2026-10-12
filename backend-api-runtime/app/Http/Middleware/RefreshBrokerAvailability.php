<?php

namespace App\Http\Middleware;

use App\Services\BrokerAvailabilityService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class RefreshBrokerAvailability
{
    public function handle(Request $request, Closure $next)
    {
        if ($request->is('api/properties', 'api/properties/nearby', 'api/broker/*', 'api/professional/workspace')) {
            // Traffic advances essential in-app reminders even on a sleeping free UAT service.
            $lock = Cache::lock('broker-availability-sweep', 30);
            if ($lock->get()) {
                try {
                    if (! Cache::has('broker-availability-swept')) {
                        app(BrokerAvailabilityService::class)->sweep();
                        Cache::put('broker-availability-swept', true, 60);
                    }
                } finally { $lock->release(); }
            }
        }
        return $next($request);
    }
}
