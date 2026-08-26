<?php
namespace App\Services;

use App\Models\User;
use App\Models\VerificationChallenge;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class VerificationCodeService
{
    public const EXPIRES_MINUTES = 10;
    public const MAX_ATTEMPTS = 5;

    public function __construct(private readonly UatTestOtpService $uatTestOtp) {}

    public function create(User $user, string $purpose, string $destination): array
    {
        VerificationChallenge::query()
            ->where('user_id',$user->id)->where('purpose',$purpose)
            ->whereNull('consumed_at')->update(['consumed_at'=>now()]);

        $code = $this->uatTestOtp->codeFor($destination) ?? (string) random_int(100000, 999999);
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
    }

    public function verify(User $user, string $purpose, string $destination, string $code): void
    {
        $challenge = VerificationChallenge::query()
            ->where('user_id',$user->id)->where('purpose',$purpose)
            ->where('destination',$destination)->whereNull('consumed_at')
            ->latest('id')->first();

        if (! $challenge || $challenge->expires_at->isPast()) {
            throw ValidationException::withMessages(['code'=>['The verification code is missing or expired.']]);
        }
        if ($challenge->attempts >= self::MAX_ATTEMPTS) {
            throw ValidationException::withMessages(['code'=>['Too many failed attempts. Request a new code.']]);
        }
        if (! Hash::check($code,$challenge->code_hash)) {
            $challenge->increment('attempts');
            throw ValidationException::withMessages(['code'=>['The verification code is incorrect.']]);
        }
        $challenge->forceFill(['consumed_at'=>now(),'attempts'=>$challenge->attempts+1])->save();
    }
}
