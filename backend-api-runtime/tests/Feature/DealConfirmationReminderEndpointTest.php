<?php

namespace Tests\Feature;

use App\Services\BrokerDealService;
use Tests\TestCase;

class DealConfirmationReminderEndpointTest extends TestCase
{
    public function test_external_clock_can_only_run_the_reminder_with_the_configured_credential(): void
    {
        $endpoint = '/api/internal/deal-confirmation-reminders';
        $token = str_repeat('k', 40);

        config(['background.deal_confirmation_reminder_token' => null]);
        $this->postJson($endpoint)->assertNotFound();

        config(['background.deal_confirmation_reminder_token' => $token]);
        $this->withToken(str_repeat('x', 40))->postJson($endpoint)->assertNotFound();

        $this->mock(BrokerDealService::class, function ($deals): void {
            $deals->shouldReceive('remindSupportOfPendingPrices')->once()->andReturn(1);
        });
        $this->withToken($token)->postJson($endpoint)->assertNoContent();
    }
}
