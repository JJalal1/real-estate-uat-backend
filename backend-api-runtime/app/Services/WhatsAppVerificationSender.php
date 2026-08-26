<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

class WhatsAppVerificationSender
{
    public function __construct(private readonly UatTestOtpService $uatTestOtp) {}

    public function sendCode(string $destination, string $code): void
    {
        if ($this->uatTestOtp->shouldBypassDelivery($destination, $code)) {
            return;
        }

        $phoneNumberId = trim((string) config('services.whatsapp.phone_number_id'));
        $accessToken = trim((string) config('services.whatsapp.access_token'));
        $template = trim((string) config('services.whatsapp.auth_template'));
        $locale = trim((string) config('services.whatsapp.locale', 'ar'));
        $apiVersion = trim((string) config('services.whatsapp.api_version', 'v23.0'));

        // Local/testing regression remains usable without secrets. Staging only
        // bypasses delivery for explicitly allowlisted UAT test phone numbers.
        // Production fails closed and UAT test OTP is rejected by UatTestOtpService.
        if ($phoneNumberId === '' || $accessToken === '' || $template === '') {
            if (app()->environment('local', 'testing')) {
                return;
            }
            throw new RuntimeException('WhatsApp verification is not configured on this server.');
        }

        $to = ltrim($destination, '+');
        $response = Http::withToken($accessToken)
            ->acceptJson()
            ->asJson()
            ->timeout(20)
            ->post("https://graph.facebook.com/{$apiVersion}/{$phoneNumberId}/messages", [
                'messaging_product' => 'whatsapp',
                'to' => $to,
                'type' => 'template',
                'template' => [
                    'name' => $template,
                    'language' => ['code' => $locale],
                    'components' => [[
                        'type' => 'body',
                        'parameters' => [[
                            'type' => 'text',
                            'text' => $code,
                        ]],
                    ]],
                ],
            ]);

        if (! $response->successful()) {
            throw new RuntimeException('WhatsApp verification delivery failed.');
        }
    }
}
