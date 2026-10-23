<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsurePermission
{
    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $user=$request->user();
        if (! $user || ! $user->hasPermission($permission)) {
            return new JsonResponse(['message'=>'You do not have permission to perform this action.','code'=>'PERMISSION_DENIED'],403);
        }
        return $next($request);
    }
}
