<?php
namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureAccountActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user instanceof User) {
            return new JsonResponse(['message'=>'Authentication required.','code'=>'AUTH_REQUIRED'],401);
        }
        if (! $user->isActive()) {
            return new JsonResponse([
                'message'=>'Verify your phone before using protected listing operations.',
                'code'=>'ACCOUNT_NOT_ACTIVE',
                'account_status'=>$user->account_status,
            ],403);
        }
        return $next($request);
    }
}
