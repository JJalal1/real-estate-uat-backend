<?php

namespace App\Services;

use RuntimeException;

/** Safe queue metadata only: never includes a token, message body or provider response. */
class PushDeliveryException extends RuntimeException
{
    public function __construct(
        public readonly int $httpStatus,
        public readonly bool $retryable,
        public readonly int $retryAfterSeconds,
    ) {
        parent::__construct('FCM request failed with HTTP '.$httpStatus.'.');
    }
}
