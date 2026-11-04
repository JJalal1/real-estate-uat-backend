<?php

namespace App\Console\Support;

use Closure;
use Illuminate\Http\Client\Response;

/** Provisioning only: honor ordinary OTP middleware, never retry listing writes. */
class UatOwnerRequestRetry
{
    public function __construct(private readonly ?Closure $pause = null) {}

    public function send(string $path, Closure $send, Closure $throttled, float $started): Response
    {
        $response=$send();
        if (!in_array($path,['/api/auth/whatsapp/start','/api/auth/whatsapp/verify'],true)) return $response;
        for ($attempt=1; $response->status()===429 && $attempt<=2; $attempt++) {
            $raw=trim((string)$response->header('Retry-After'));
            if ($raw==='' || !ctype_digit($raw) || strlen($raw)>2) return $response;
            $seconds=(int)$raw+1;
            if ($seconds<1 || $seconds>65 || microtime(true)-$started+$seconds>=480) return $response;
            $throttled($seconds,$attempt);
            if ($this->pause!==null) ($this->pause)($seconds); else sleep($seconds);
            $response=$send();
        }
        return $response;
    }
}
