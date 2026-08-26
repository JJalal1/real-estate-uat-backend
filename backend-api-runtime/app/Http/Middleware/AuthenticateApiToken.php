<?php
namespace App\Http\Middleware;

use App\Services\ApiTokenService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateApiToken
{
    public function __construct(private readonly ApiTokenService $tokens) {}
    public function handle(Request $request, Closure $next): Response
    {
        $this->tokens->authenticate($request, true);
        return $next($request);
    }
}
