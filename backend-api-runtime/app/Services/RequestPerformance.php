<?php

namespace App\Services;

/** Request-local counters only. Never retain SQL, bindings, URLs or credentials. */
final class RequestPerformance
{
    public const ATTRIBUTE = 'aqer_request_performance';

    public int $queries = 0;
    public float $databaseMs = 0;
    public int $storageRequests = 0;
    public float $storageMs = 0;

    public function query(float $milliseconds): void
    {
        $this->queries++;
        $this->databaseMs += $milliseconds;
    }

    public function storage(float $seconds): void
    {
        $this->storageRequests++;
        $this->storageMs += $seconds * 1000;
    }
}
