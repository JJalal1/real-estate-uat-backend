<?php
namespace App\Http\Middleware;

use App\Services\ApiTokenService;
use Closure;
use Illuminate\Contracts\Auth\Middleware\AuthenticatesRequests;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

// Laravel uses this contract to authenticate before throttling and bindings.
// Otherwise authenticated users behind one proxy share an anonymous IP bucket.
class AuthenticateApiToken implements AuthenticatesRequests
{
    public function __construct(private readonly ApiTokenService $tokens) {}
    public function handle(Request $request, Closure $next): Response
    {
        $this->tokens->authenticate($request, true);
        return $next($request);
    }
}
