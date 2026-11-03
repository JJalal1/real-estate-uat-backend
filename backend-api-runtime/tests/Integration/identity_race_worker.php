<?php

declare(strict_types=1);

use App\Models\Property;
use App\Models\User;
use App\Services\ListingWorkflowService;
use App\Services\PropertyIdentityService;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Contracts\Http\Kernel as HttpKernel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

if (getenv('DB_CONNECTION') !== 'pgsql'
    || getenv('DB_HOST') !== '127.0.0.1'
    || getenv('DB_PORT') !== '55441'
    || getenv('DB_DATABASE') !== 'aqer_identity_race_test') {
    fwrite(STDERR, "Identity race worker requires the named loopback test database.\n");
    exit(3);
}

[$script, $action, $userId, $propertyId, $gateDir, $slot] = $argv + [null, null, null, null, null, null];
if (! in_array($action, ['submit', 'submit_fail', 'retry', 'claim', 'approve_http'], true)
    || ! ctype_digit((string) $userId) || ! ctype_digit((string) $propertyId)
    || ! in_array($slot, ['a', 'b'], true) || ! is_dir((string) $gateDir)) {
    fwrite(STDERR, "Invalid synthetic worker arguments.\n");
    exit(3);
}

require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

if ($action === 'submit_fail') {
    $app->instance(PropertyIdentityService::class, new class extends PropertyIdentityService {
        public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
        {
            throw new RuntimeException('Synthetic identity processor failure');
        }
    });
}

$pid = (int) DB::selectOne("SELECT pg_backend_pid() AS pid, set_config('application_name', ?, false)",
    ['aqer_identity_race_' . $action . '_' . $slot])->pid;
file_put_contents($gateDir . '/ready-' . $slot . '.json', json_encode(['pid' => $pid, 'action' => $action]));
$deadline = microtime(true) + 15;
while (! is_file($gateDir . '/go')) {
    if (microtime(true) > $deadline) {
        fwrite(STDERR, "Synthetic barrier timed out.\n");
        exit(4);
    }
    usleep(10000);
}

try {
    $actor = User::query()->findOrFail((int) $userId);
    $listing = Property::query()->findOrFail((int) $propertyId);
    if (in_array($action, ['submit', 'submit_fail'], true)) {
        $result = $app->make(ListingWorkflowService::class)->submit(
            $actor, $listing, Request::create('/synthetic-identity-race', 'POST')
        );
        $output = ['ok' => true, 'status' => $result->status,
            'review_status' => $result->review_status,
            'duplicate_check_status' => $result->duplicate_check_status];
    } elseif ($action === 'retry') {
        $result = $app->make(ListingWorkflowService::class)->processSubmittedIdentity($actor, $listing);
        $output = ['ok' => true, 'decision' => $result['decision'], 'status' => $result['status']];
    } elseif ($action === 'approve_http') {
        $plain = 'race_' . substr(hash('sha512', $actor->email), 0, 76);
        $request = Request::create("/api/admin/listing-review/listings/$propertyId/approve", 'POST',
            [], [], [], [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_ACCEPT' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer ' . $plain,
            ], json_encode(['reason' => 'Synthetic support reviewed the property evidence.'], JSON_THROW_ON_ERROR));
        $kernel = $app->make(HttpKernel::class);
        $response = $kernel->handle($request);
        $kernel->terminate($request, $response);
        $body = json_decode($response->getContent(), true);
        $output = [
            'ok' => $response->getStatusCode() === 200,
            'http_status' => $response->getStatusCode(),
            'status' => $body['data']['status'] ?? null,
            'review_status' => $body['data']['review_status'] ?? null,
            'error_type' => $body['exception'] ?? null,
            'message' => mb_substr((string) ($body['message'] ?? ''), 0, 200),
        ];
    } else {
        $app->make(PropertyIdentityService::class)->ensureRepresentation($listing);
        $output = ['ok' => true, 'claim' => 'active'];
    }
    echo json_encode($output, JSON_THROW_ON_ERROR) . "\n";
} catch (Throwable $error) {
    echo json_encode(['ok' => false, 'error_type' => $error::class,
        'http_status' => method_exists($error, 'getStatusCode') ? $error->getStatusCode() : null],
        JSON_THROW_ON_ERROR) . "\n";
    exit(2);
}
