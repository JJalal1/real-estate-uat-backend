<?php

namespace App\Services;

use RuntimeException;

class UatTestOtpService
{
    public function codeFor(string $destination): ?string
    {
        if (! (bool) config('services.whatsapp.uat_test_otp.enabled', false)) {
            return null;
        }

        if (app()->environment('production')) {
            throw new RuntimeException('UAT test OTP must never be enabled in production.');
        }

        if (! app()->environment('staging', 'testing')) {
            return null;
        }

        $code = trim((string) config('services.whatsapp.uat_test_otp.code', ''));
        if (! preg_match('/^[0-9]{6}$/', $code)) {
            throw new RuntimeException('UAT test OTP code must be exactly six digits.');
        }

        $phones = config('services.whatsapp.uat_test_otp.phone_numbers', []);
        if (! is_array($phones)) {
            throw new RuntimeException('UAT test phone number allowlist is invalid.');
        }

        $allowed = array_values(array_filter(array_map(
            static fn ($value): string => trim((string) $value),
            $phones,
        ), static fn (string $value): bool => $value !== ''));

        return in_array($destination, $allowed, true) ? $code : null;
    }

    public function shouldBypassDelivery(string $destination, string $code): bool
    {
        $testCode = $this->codeFor($destination);

        return $testCode !== null && hash_equals($testCode, $code);
    }
}
