<?php

namespace Tests\Unit;

use App\Http\Middleware\RequestObservability;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

class RequestObservabilityTest extends TestCase
{
    public function test_it_adds_a_request_id_without_exposing_request_data(): void
    {
        $request = Request::create('/api/test-observability', 'GET', ['private' => 'do-not-log']);
        $middleware = new RequestObservability();

        $response = $middleware->handle(
            $request,
            fn () => new Response('ok', 200),
        );

        $requestId = $response->headers->get('X-Request-ID');
        $this->assertNotEmpty($requestId);
        $this->assertSame($requestId, $request->attributes->get('request_id'));
    }
}
