<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\VerificationChallenge;
use App\Services\AccountErasureService;
use App\Services\EmailVerificationSender;
use App\Services\VerificationCodeService;
use App\Services\WhatsAppVerificationSender;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

class AccountDeletionWebController extends Controller
{
    public function show(Request $request): View
    {
        return view('account-deletion', [
            'otpStarted' => (bool) $request->session()->get('account_deletion_started', false),
            'completed' => (bool) $request->session()->pull('account_deletion_completed', false),
        ]);
    }

    public function start(
        Request $request,
        VerificationCodeService $verification,
        WhatsAppVerificationSender $whatsapp,
        EmailVerificationSender $email,
    ): RedirectResponse {
        $v=$request->validate(['login'=>['required','string','max:190']]);
        $login=trim((string)$v['login']);
        $key='web-account-deletion:'.hash('sha256',Str::lower($login));
        abort_if(RateLimiter::tooManyAttempts($key,5),429,'طلبات كثيرة. حاول لاحقًا.');
        RateLimiter::hit($key,3600);

        [$user,$destination,$channel]=$this->resolveUser($login);
        $request->session()->forget([
            'account_deletion_user_id',
            'account_deletion_destination',
            'account_deletion_started',
        ]);
        $request->session()->put('account_deletion_started', true);

        if ($channel==='email') $email->ensureConfigured();

        if ($user && $destination) {
            $created=$verification->create(
                $user,
                VerificationChallenge::PURPOSE_ACCOUNT_DELETION,
                $destination,
                allowUatCode:$channel==='phone',
            );
            if ($channel==='email') {
                $email->sendCode($destination,(string)$created['code']);
            } else {
                $whatsapp->sendCode($destination,(string)$created['code']);
            }
            $request->session()->put([
                'account_deletion_user_id'=>$user->id,
                'account_deletion_destination'=>$destination,
            ]);
        }

        return back()->with('status','إذا كان الحساب موجودًا ومؤهلًا، أرسلنا رمز تحقق إلى وسيلة الدخول المسجلة.');
    }

    public function confirm(
        Request $request,
        VerificationCodeService $verification,
        AccountErasureService $erasure,
    ): RedirectResponse {
        $v=$request->validate([
            'code'=>['required','digits:6'],
            'confirm_phrase'=>['required','in:حذف حسابي نهائيًا'],
        ]);

        $userId=(int)$request->session()->get('account_deletion_user_id',0);
        $destination=(string)$request->session()->get('account_deletion_destination','');
        if ($userId<=0 || $destination==='') {
            throw ValidationException::withMessages(['code'=>['رمز التحقق غير صحيح أو انتهت صلاحيته.']]);
        }

        $user=User::query()->find($userId);
        if (! $user || $user->account_status===User::STATUS_DELETED) {
            throw ValidationException::withMessages(['code'=>['تعذر إكمال الطلب.']]);
        }

        $verification->verify(
            $user,
            VerificationChallenge::PURPOSE_ACCOUNT_DELETION,
            $destination,
            (string)$v['code'],
        );
        $erasure->erase($user,$request);

        $request->session()->invalidate();
        $request->session()->regenerateToken();
        $request->session()->put('account_deletion_completed',true);

        return redirect('/account-deletion');
    }

    private function resolveUser(string $login): array
    {
        $email=filter_var($login,FILTER_VALIDATE_EMAIL)
            ? Str::lower($login)
            : null;
        if ($email) {
            $user=User::query()
                ->where('email',$email)
                ->whereNot('account_status',User::STATUS_DELETED)
                ->first();
            return [
                $user,
                $user?->email_verified_at ? $user->email : null,
                'email',
            ];
        }

        $phone=$this->normalizePhone($login);
        if ($phone===null) return [null,null,'phone'];
        $user=User::query()
            ->where('phone',$phone)
            ->whereNot('account_status',User::STATUS_DELETED)
            ->first();
        return [
            $user,
            $user?->phone_verified_at ? $user->phone : null,
            'phone',
        ];
    }

    private function normalizePhone(string $value): ?string
    {
        $value=strtr(trim($value),[
            '٠'=>'0','١'=>'1','٢'=>'2','٣'=>'3','٤'=>'4','٥'=>'5','٦'=>'6','٧'=>'7','٨'=>'8','٩'=>'9',
            '۰'=>'0','۱'=>'1','۲'=>'2','۳'=>'3','۴'=>'4','۵'=>'5','۶'=>'6','۷'=>'7','۸'=>'8','۹'=>'9',
        ]);
        $value=preg_replace('/[\p{Cf}\p{Z}\s\-().]/u','',$value) ?? '';
        if (str_starts_with($value,'00')) $value='+'.substr($value,2);
        return preg_match('/^\+?[0-9]{7,20}$/',$value) ? $value : null;
    }
}
