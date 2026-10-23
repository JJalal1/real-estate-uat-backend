<?php
namespace App\Services;

use Illuminate\Mail\Message;
use Illuminate\Support\Facades\Mail;
use Symfony\Component\HttpKernel\Exception\HttpException;

class EmailVerificationSender
{
    public function ensureConfigured(): void
    {
        // Never expose an OTP in a log transport, or report a dummy delivery as sent.
        $mailer = (string) config('mail.default');
        $transport = (string) config("mail.mailers.{$mailer}.transport");
        if (!app()->environment('local', 'testing') &&
            !in_array($transport, ['smtp', 'ses', 'ses-v2', 'postmark', 'resend', 'mailgun', 'sendmail'], true)) {
            throw new HttpException(503, 'الدخول بالبريد غير مفعّل حاليًا. استخدم واتساب أو أعد المحاولة لاحقًا.');
        }
    }

    public function sendCode(string $email, string $code): void
    {
        $this->ensureConfigured();
        // The in-memory mail transport is used only by the local regression harness.
        $mailer = app()->environment('local', 'testing') ? 'array' : (string) config('mail.default');
        try {
            Mail::mailer($mailer)->raw("رمز التحقق الخاص بك: {$code}\nصالح لمدة 10 دقائق. لا تشاركه مع أي شخص.",
                fn (Message $message) => $message->to($email)->subject('رمز الدخول إلى عقارات حولك'));
        } catch (\Throwable) {
            // Do not include provider exceptions, destinations or plaintext OTPs in logs.
            throw new HttpException(503, 'تعذر إرسال رمز البريد. جرّب مجددًا أو استخدم واتساب.');
        }
    }
}
