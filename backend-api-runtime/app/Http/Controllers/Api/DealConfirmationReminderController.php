<?php

namespace App\Http\Controllers\Api;

use App\Services\BrokerDealService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

final class DealConfirmationReminderController
{
    public function __invoke(Request $request, BrokerDealService $deals): Response
    {
        $token = (string) config('background.deal_confirmation_reminder_token');
        abort_unless(strlen($token) >= 32
            && hash_equals($token, (string) $request->bearerToken()), 404);

        $deals->remindSupportOfPendingPrices();

        return response()->noContent();
    }
}
