<?php
namespace App\Services;

use App\Models\ApiToken;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;

class ApiTokenService
{
    public const TOKEN_TTL_DAYS = 30;

    public function issue(User $user, Request $request, string $name = 'android'): array
    {
        $plain = 're6_'.Str::random(80);
        $expiresAt = now()->addDays(self::TOKEN_TTL_DAYS);

        $user->apiTokens()->create([
            'name'=>$name,
            'token_hash'=>hash('sha256',$plain),
            'token_prefix'=>substr($plain,0,12),
            'expires_at'=>$expiresAt,
            'ip_address'=>substr((string)$request->ip(),0,45),
            'user_agent'=>substr((string)$request->userAgent(),0,500),
        ]);

        return ['plain_text_token'=>$plain,'expires_at'=>$expiresAt->toIso8601String()];
    }

    public function authenticate(Request $request, bool $required = true): ?User
    {
        $plain = trim((string)$request->bearerToken());
        if ($plain === '') {
            if ($required) throw new HttpException(401,'Authentication required.');
            return null;
        }

        $token = ApiToken::query()->with('user')
            ->where('token_hash',hash('sha256',$plain))->first();

        if (! $token || ! $token->user) {
            if ($required) throw new HttpException(401,'Invalid authentication token.');
            return null;
        }

        if ($token->expires_at !== null && $token->expires_at->isPast()) {
            $token->delete();
            if ($required) throw new HttpException(401,'Authentication token expired.');
            return null;
        }

        $user = $token->user;
        if ($user->account_status === User::STATUS_SUSPENDED) {
            if ($required) throw new HttpException(403,'This account is suspended.');
            return null;
        }
        if ($user->account_status === User::STATUS_BANNED) {
            if ($required) throw new HttpException(403,'This account is banned.');
            return null;
        }

        if ($token->last_used_at === null || $token->last_used_at->lt(now()->subMinutes(5))) {
            $token->forceFill(['last_used_at'=>now()])->save();
        }

        $request->attributes->set('stage6_api_token_id',$token->id);
        $request->setUserResolver(fn () => $user);
        return $user;
    }

    public function revokeCurrent(Request $request): void
    {
        $id = $request->attributes->get('stage6_api_token_id');
        if ($id !== null) ApiToken::query()->whereKey($id)->delete();
    }

    public function revokeAll(User $user): void { $user->apiTokens()->delete(); }
}
