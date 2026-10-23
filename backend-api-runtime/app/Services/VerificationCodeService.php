<?php
namespace App\Services;

use App\Models\User;
use App\Models\VerificationChallenge;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class VerificationCodeService
{
    public const EXPIRES_MINUTES = 10;
    public const MAX_ATTEMPTS = 5;

    public function __construct(private readonly UatTestOtpService $uatTestOtp) {}

    public function create(User $user, string $purpose, string $destination, bool $allowUatCode = true): array
    {
        return DB::transaction(function () use ($user, $purpose, $destination, $allowUatCode) {
        User::query()->whereKey($user->id)->lockForUpdate()->firstOrFail();
        VerificationChallenge::query()
            ->where('user_id',$user->id)->where('purpose',$purpose)
            ->whereNull('consumed_at')->update(['consumed_at'=>now()]);

        $code = ($allowUatCode ? $this->uatTestOtp->codeFor($destination) : null) ?? (string) random_int(100000, 999999);
        $challenge = $user->verificationChallenges()->create([
            'destination'=>$destination,
            'purpose'=>$purpose,
            'code_hash'=>Hash::make($code),
            'attempts'=>0,
            'expires_at'=>now()->addMinutes(self::EXPIRES_MINUTES),
        ]);

        return [
            'challenge'=>$challenge,
            // Internal plaintext code is used only by the delivery service in this request.
            // It is never persisted; API responses expose debug_code only in local/testing.
            'code'=>$code,
            'debug_code'=>app()->environment('local', 'testing') ? $code : null,
        ];
        });
    }

    public function verify(User $user, string $purpose, string $destination, string $code): void
    {
        // Commit failed-attempt counters as well as successful consumption, and
        // serialize replay attempts before the caller issues an API token.
        $error = DB::transaction(function () use ($user, $purpose, $destination, $code) {
        $challenge = VerificationChallenge::query()
            ->where('user_id',$user->id)->where('purpose',$purpose)
            ->where('destination',$destination)->whereNull('consumed_at')
            ->latest('id')->lockForUpdate()->first();

        if (! $challenge || $challenge->expires_at->isPast()) {
            return 'The verification code is missing or expired.';
        }
        if ($challenge->attempts >= self::MAX_ATTEMPTS) {
            return 'Too many failed attempts. Request a new code.';
        }
        if (! Hash::check($code,$challenge->code_hash)) {
            $challenge->increment('attempts');
            return 'The verification code is incorrect.';
        }
        $challenge->forceFill(['consumed_at'=>now(),'attempts'=>$challenge->attempts+1])->save();
        return null;
        });
        if ($error !== null) throw ValidationException::withMessages(['code'=>[$error]]);
    }
}

