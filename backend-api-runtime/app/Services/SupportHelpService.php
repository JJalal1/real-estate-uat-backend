<?php

namespace App\Services;

use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportCaseMessage;
use App\Models\User;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\DB;

class SupportHelpService
{
    private const FAQ = [
        'publish' => ['كيف أنشر إعلانًا؟', 'افتح إضافة عقار، وأكمل بيانات الإعلان والصور والموقع، ثم أرسله للمراجعة. تقدر تتابع حالته من إعلاناتك.', null],
        'review' => ['أين أتابع حالة إعلاني؟', 'افتح إعلاناتك واختر الإعلان. إذا أُعيد للتصحيح، يظهر سبب الإرجاع في الإشعارات ويمكنك تعديل الإعلان وإرساله مجددًا.', '/notifications'],
        'payments' => ['أين أشوف مستحقات المنصة؟', 'من حساب الدلال افتح الحساب المالي ثم المستحقات. اختر مستحقًا لعرض المبلغ وطرق الدفع ورفع الإيصال.', '/broker/finance'],
        'reports' => ['كيف أتابع بلاغي أو طلب الدعم؟', 'افتح الدعم ثم طلباتي. عند فتح الطلب تظهر حالته وردود الدعم، وتقدر تضيف توضيحًا إذا طلبه الموظف.', '/support?view=cases'],
        'map' => ['كيف أحدد موقع العقار؟', 'من خطوة الموقع في نموذج الإعلان افتح الخريطة، وحرّك الدبوس إلى مكان العقار، ثم أكّد النقطة قبل إرسال الإعلان.', null],
        'support' => ['كيف أكلم موظف الدعم؟', 'من حسابي افتح الدعم ثم «تحدّث مع موظف الدعم». اكتب رسالتك وتابع الرد من نفس المحادثة.', '/support'],
    ];

    public function __construct(
        private readonly GeminiClient $gemini,
        private readonly SupportTaskService $tasks,
        private readonly PlatformSettingsService $settings,
    ) {}

    public function questions(): array
    {
        return array_map(fn ($item) => ['question' => $item[0], 'answer' => $item[1]], array_values(self::FAQ));
    }

    public function tryAnswer(User $user, string $question): ?array
    {
        if (preg_match('/احتيال|تهديد|اعترض|أعترض|اوقف|إيقاف|اريد موظف|أريد موظف|موظف الآن|كلمني|ما انحلت|ما انحل/u', $question)) return null;

        if (preg_match('/(?:إعلاني|اعلاني|إعلان رقم|اعلان رقم)/u', $question)
            && preg_match('/ليش|لماذا|سبب|نزل|الحال[ةه]|رفض|ارجع|إرجاع/u', $question)) {
            $listings = Property::query()->where('user_id', $user->id);
            $normalized = strtr($question, ['٠'=>'0','١'=>'1','٢'=>'2','٣'=>'3','٤'=>'4','٥'=>'5','٦'=>'6','٧'=>'7','٨'=>'8','٩'=>'9']);
            if (preg_match('/(?:رقم|#)\s*(\d{1,12})(?!\d)/u', $normalized, $match)) {
                $listings->whereKey((int) $match[1]);
            }
            $match = $listings->latest('id')->limit(2)->get(['id', 'review_status', 'last_review_reason', 'status']);
            if ($match->count() !== 1) return null;
            $listing = $match->first();
            $status = match ($listing->review_status) {
                'submitted' => 'بانتظار المراجعة',
                'under_review' => 'قيد التحقيق',
                'returned_for_correction' => 'أُعيد للتصحيح',
                'rejected_duplicate' => 'رُفض بسبب التكرار',
                'rejected_blocked' => 'رُفض الإعلان',
                'approved' => 'اعتُمد الإعلان',
                default => 'مسودة',
            };
            $reason = trim((string) $listing->last_review_reason);

            return [
                'body' => 'حالة إعلانك: '.$status.($reason === '' ? '.' : "\n".$reason),
                'destination' => '/support/listing-decision/'.$listing->id,
            ];
        }

        $faq = match (true) {
            (bool) preg_match('/كيف.*(أنشر|انشر|أضيف|اضيف).*عقار|كيف.*(أنشر|انشر).*إعلان/u', $question) => 'publish',
            (bool) preg_match('/وين.*المستحق|أين.*المستحق|كيف.*أرفع.*(الإيصال|الايصال)/u', $question) => 'payments',
            (bool) preg_match('/(?:كيف|وين|أين).*(?:أتابع|اتابع).*بلاغ/u', $question) => 'reports',
            (bool) preg_match('/كيف.*(احدد|أحدد).*(الموقع|موقع|الخريط)/u', $question) => 'map',
            default => null,
        };
        if ($faq === null && $this->gemini->available()) {
            try {
                // The provider selects a help topic only. It cannot make a
                // decision or generate an unverified answer for the requester.
                $result = $this->gemini->object(
                    'Choose the matching FAQ id only if the question is fully answered by that FAQ. Choose human for disputes, complaints, account-specific issues, or uncertainty.',
                    ['question' => mb_substr($question, 0, 1200), 'topics' => array_map(fn ($item) => $item[0], self::FAQ)],
                    ['type' => 'object', 'properties' => ['id' => ['type' => 'string', 'enum' => [...array_keys(self::FAQ), 'human']]], 'required' => ['id']],
                );
                if (is_string($result['id'] ?? null)) $faq = $result['id'];
            } catch (HttpResponseException) {
                return null;
            }
        }
        if (!isset(self::FAQ[$faq])) return null;

        return ['body' => self::FAQ[$faq][1], 'destination' => self::FAQ[$faq][2]];
    }

    public function respond(SupportCase $case, User $user): SupportCase
    {
        if ($case->channel !== 'assistant') return $case;
        $question = $case->messages()->reorder()->where('actor_role', 'requester')->latest('id')->first();
        if (!$question) return $case;
        if ($case->messages()->where('actor_role', 'assistant')->where('id', '>', $question->id)->exists()) return $case;
        $answer = DB::table('support_case_files')->where('support_case_message_id', $question->id)->exists()
            ? null : $this->tryAnswer($user, $question->body);

        return DB::transaction(function () use ($case, $question, $answer): SupportCase {
            $locked = SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            if ($locked->channel !== 'assistant' || (int) $locked->messages()->max('id') !== (int) $question->id) return $locked;
            if ($answer === null) return $this->transferLocked($locked);
            $this->addAssistantMessage($locked, $answer['body'], $answer['destination']);
            $locked->forceFill(['last_activity_at' => now()])->save();

            return $locked;
        });
    }

    public function handoff(SupportCase $case, User $user): SupportCase
    {
        abort_unless((int) $case->requester_user_id === (int) $user->id, 404);

        return DB::transaction(function () use ($case): SupportCase {
            $locked = SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            if ($locked->channel !== 'assistant') return $locked;

            return $this->transferLocked($locked);
        });
    }

    private function transferLocked(SupportCase $case): SupportCase
    {
        $case->forceFill([
            'channel' => 'human',
            'sla_due_at' => now()->addHours((int) $this->settings->get('support.sla_hours', 48)),
            'last_activity_at' => now(),
        ])->save();
        $this->addAssistantMessage($case, 'حوّلنا محادثتك إلى الدعم. بانتظار موظف الدعم.');
        $this->tasks->projectSupportCase($case);

        return $case;
    }

    private function addAssistantMessage(SupportCase $case, string $body, ?string $actionPath = null): void
    {
        SupportCaseMessage::query()->create([
            'support_case_id' => $case->id, 'actor_role' => 'assistant', 'actor_name_snapshot' => 'المساعد الذكي',
            'is_internal' => false, 'body' => $body, 'action_path' => $actionPath, 'created_at' => now(),
        ]);
    }
}
