<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertySaiService
{
    public const OWNER_SALE_RATE = 1.0;
    public const OWNER_RENT_RATE = 20.0;
    public const BROKER_SALE_MAX = 5.0;
    public const BROKER_RENT_MAX = 100.0;
    public const PLATFORM_BROKER_SHARE = 20.0;
    public const BROKER_NET_SHARE = 80.0;

    public function __construct(private readonly AuditLogService $audit) {}

    public function configure(
        User $actor,
        Property $property,
        string $payer,
        ?float $brokerRate,
        ?string $platformTermsDecision,
        Request $request,
        bool $deferPlatformTerms = false,
        string $amountType = 'percentage',
        ?float $fixedAmount = null,
    ): PropertySaiTerm {
        if ((int) $property->user_id !== (int) $actor->id) {
            abort(403, 'Only the listing advertiser can configure sai terms.');
        }

        return DB::transaction(function () use ($actor, $property, $payer, $brokerRate, $platformTermsDecision, $request, $deferPlatformTerms, $amountType, $fixedAmount): PropertySaiTerm {
            $locked = Property::query()->whereKey($property->id)->lockForUpdate()->firstOrFail();
            if ($locked->status === 'published'
                || in_array($locked->review_status, ['submitted', 'under_review', 'rejected_blocked'], true)) {
                throw new ConflictHttpException('عدّل الإعلان أولاً ليعود إلى المسودة، ثم أكد شروط السعي وأرسله للمراجعة من جديد.');
            }

            if ($deferPlatformTerms && ((int) $locked->listing_input_version < 6 || $platformTermsDecision !== null)) {
                throw ValidationException::withMessages(['defer_platform_terms' => ['تأجيل الإقرار متاح لمسودة النموذج الجديد دون قرار قبول أو رفض مسبق.']]);
            }
            $advertiserType = $this->advertiserType($actor);
            $purpose = (string) $locked->purpose;
            $this->validatePayer($purpose, $payer, true);
            if (! in_array($amountType, ['percentage', 'fixed'], true)
                || ($amountType === 'fixed' && $brokerRate !== null)
                || ($amountType === 'percentage' && $fixedAmount !== null)) {
                throw ValidationException::withMessages(['sai_amount_type' => ['اختر نسبة مئوية أو مبلغًا ثابتًا دون الجمع بينهما.']]);
            }

            $sourceMode = 'owner_fixed';
            $requestedRate = null;
            $effectiveRate = $this->fixedRate($purpose);
            $platformShare = 100.0;
            $brokerShare = 0.0;
            $termsStatus = 'not_required';
            $acceptedAt = null;
            $rejectedAt = null;
            $storedAmountType = 'percentage';
            $storedFixedAmount = null;
            $fixedCurrency = null;

            if ($advertiserType === 'owner') {
                if ($brokerRate !== null || $amountType === 'fixed') {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => ['نسبة سعي المالك ثابتة ولا يمكن تغييرها.'],
                    ]);
                }
            } else {
                if ($amountType === 'percentage' && $brokerRate === null) {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => ['حدد نسبة السعي للدلال/المكتب من صفر وحتى الحد المسموح.'],
                    ]);
                }

                $max = $this->brokerMaxRate($purpose);
                if ($amountType === 'percentage' && (! is_finite($brokerRate) || $brokerRate < 0 || $brokerRate > $max)) {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => [
                            $purpose === 'sale'
                                ? 'السعي في البيع يجب أن يكون بين 0% و5%.'
                                : 'السعي في الإيجار يجب أن يكون بين 0% و100% من إيجار الشهر الأول.',
                        ],
                    ]);
                }

                if ($amountType === 'fixed' && ($fixedAmount === null || ! is_finite($fixedAmount)
                    || $fixedAmount < 0 || $fixedAmount > $this->fixedAmountLimit($locked))) {
                    throw ValidationException::withMessages(['fixed_sai_amount' => ['أدخل مبلغ سعي صحيحًا ضمن الحد المسموح من سعر العقار أو إيجار الشهر الأول.']]);
                }
                $requestedRate = $amountType === 'fixed' ? null : round($brokerRate, 2);
                $custom = $amountType === 'fixed' ? round($fixedAmount, 2) > 0 : $requestedRate > 0;
                if ($custom) {
                    $sourceMode = 'broker_custom';
                    $effectiveRate = $amountType === 'fixed' ? 0.0 : $requestedRate;
                    if ($amountType === 'fixed') {
                        $storedAmountType = 'fixed';
                        $storedFixedAmount = round($fixedAmount, 2);
                        $fixedCurrency = (string) $locked->currency;
                    }
                    $platformShare = self::PLATFORM_BROKER_SHARE;
                    $brokerShare = self::BROKER_NET_SHARE;

                    if (! $deferPlatformTerms && ! in_array($platformTermsDecision, ['accept', 'reject'], true)) {
                        throw ValidationException::withMessages([
                            'platform_terms_decision' => ['يجب قبول أو رفض شرط نسبة التطبيق قبل المتابعة.'],
                        ]);
                    }
                    $termsStatus = $deferPlatformTerms ? 'pending' : ($platformTermsDecision === 'accept' ? 'accepted' : 'rejected');
                    $acceptedAt = $termsStatus === 'accepted' ? now() : null;
                    $rejectedAt = $termsStatus === 'rejected' ? now() : null;
                } else {
                    // 0% means no broker/office sai. It never means a free
                    // transaction: the fixed platform sai becomes effective.
                    $sourceMode = 'platform_fallback';
                    $requestedRate = 0.0;
                    $effectiveRate = $this->fixedRate($purpose);
                    $platformShare = 100.0;
                    $brokerShare = 0.0;
                    $termsStatus = 'not_required';
                }
            }

            $basis = $purpose === 'sale' ? 'final_sale_value' : 'first_month_rent';
            $nextVersion = ((int) PropertySaiTerm::query()->where('property_id', $locked->id)->max('version')) + 1;

            $candidate = [
                'property_id' => (int) $locked->id,
                'version' => $nextVersion,
                'advertiser_type' => $advertiserType,
                'purpose' => $purpose,
                'source_mode' => $sourceMode,
                'requested_broker_rate_percent' => $requestedRate,
                'sai_rate_percent' => round($effectiveRate, 2),
                'sai_amount_type' => $storedAmountType,
                'fixed_sai_amount' => $storedFixedAmount,
                'fixed_sai_currency' => $fixedCurrency,
                'payer' => $payer,
                'calculation_basis' => $basis,
                'platform_share_percent' => $platformShare,
                'broker_share_percent' => $brokerShare,
                'platform_terms_status' => $termsStatus,
                'platform_terms_accepted_at' => $acceptedAt,
                'platform_terms_rejected_at' => $rejectedAt,
                'created_by_user_id' => (int) $actor->id,
            ];

            $current = $locked->current_sai_term_id
                ? PropertySaiTerm::query()->find($locked->current_sai_term_id)
                : null;
            if ($current && $this->equivalent($current, $candidate)) {
                return $current;
            }

            $term = PropertySaiTerm::query()->create($candidate);
            $locked->forceFill(['current_sai_term_id' => $term->id])->save();

            $this->audit->record(
                $actor,
                'listing.sai_terms_version_created',
                $locked,
                [
                    'sai_term_id' => $term->id,
                    'version' => $term->version,
                    'advertiser_type' => $advertiserType,
                    'purpose' => $purpose,
                    'source_mode' => $sourceMode,
                    'sai_rate_percent' => (float) $term->sai_rate_percent,
                    'sai_amount_type' => $storedAmountType,
                    'fixed_sai_amount' => $storedFixedAmount,
                    'payer' => $payer,
                    'platform_terms_status' => $termsStatus,
                ],
                $request,
                $actor->id,
            );

            return $term;
        });
    }

    public function assertReadyForSubmission(Property $property, User $advertiser): PropertySaiTerm
    {
        $term = $property->current_sai_term_id
            ? PropertySaiTerm::query()->find($property->current_sai_term_id)
            : null;

        if (! $term) {
            throw new ConflictHttpException('يجب تحديد شروط السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.');
        }

        $advertiserType = $this->advertiserType($advertiser);
        if ($term->purpose !== $property->purpose || $term->advertiser_type !== $advertiserType) {
            throw new ConflictHttpException('تغير نوع الإعلان أو صفة المعلن. أعد تأكيد شروط السعي قبل المتابعة.');
        }

        $this->validatePayer($term->purpose, $term->payer);
        $fixed = $this->fixedRate($term->purpose);

        if ($advertiserType === 'owner') {
            if ($term->source_mode !== 'owner_fixed'
                || $term->sai_amount_type !== 'percentage'
                || abs((float) $term->sai_rate_percent - $fixed) > 0.001
                || (float) $term->platform_share_percent !== 100.0
                || (float) $term->broker_share_percent !== 0.0) {
                throw new ConflictHttpException('شروط سعي المالك غير مطابقة للسياسة المعتمدة. أعد تحديد من يتحمل السعي.');
            }
            return $term;
        }

        if ($term->sai_amount_type === 'fixed') {
            if ($term->source_mode !== 'broker_custom' || (float) $term->fixed_sai_amount <= 0
                || (float) $term->fixed_sai_amount > $this->fixedAmountLimit($property)
                || $term->fixed_sai_currency !== $property->currency
                || (float) $term->platform_share_percent !== self::PLATFORM_BROKER_SHARE
                || (float) $term->broker_share_percent !== self::BROKER_NET_SHARE
                || ! in_array($term->platform_terms_status, ['accepted', 'pending'], true)) {
                throw new ConflictHttpException('راجع مبلغ السعي الثابت وعملته وحدوده قبل إرسال الإعلان.');
            }
            return $term;
        }

        $requested = (float) ($term->requested_broker_rate_percent ?? -1);
        if ($requested < 0 || $requested > $this->brokerMaxRate($term->purpose)) {
            throw new ConflictHttpException('نسبة السعي للدلال/المكتب خارج الحد المسموح.');
        }

        if ($requested > 0) {
            if ($term->source_mode !== 'broker_custom'
                || abs((float) $term->sai_rate_percent - $requested) > 0.001
                || (float) $term->platform_share_percent !== self::PLATFORM_BROKER_SHARE
                || (float) $term->broker_share_percent !== self::BROKER_NET_SHARE
                || ! in_array($term->platform_terms_status, ['accepted', 'pending'], true)) {
                throw new ConflictHttpException('يجب قبول شرط نسبة التطبيق من مبلغ السعي قبل نشر الإعلان.');
            }
            return $term;
        }

        if ($term->source_mode !== 'platform_fallback'
            || abs((float) $term->sai_rate_percent - $fixed) > 0.001
            || (float) $term->platform_share_percent !== 100.0
            || (float) $term->broker_share_percent !== 0.0) {
            throw new ConflictHttpException('سعي 0% للدلال/المكتب يجب أن يفعّل السعي الثابت تلقائيًا.');
        }

        return $term;
    }

    public function publicData(Property $property): ?array
    {
        $term = $this->currentTerm($property);
        if (! $term || $term->purpose !== $property->purpose) {
            return null;
        }

        $rate = (float) $term->sai_rate_percent;
        $label = $this->payerLabel($term->purpose, $term->payer);

        return [
            'rate_percent' => $term->sai_amount_type === 'fixed' ? null : $rate,
            'amount_type' => $term->sai_amount_type,
            'fixed_amount' => $term->fixed_sai_amount,
            'currency' => $term->fixed_sai_currency,
            'payer' => $term->payer,
            'payer_label' => $label,
            'calculation_basis' => $term->calculation_basis,
            'display_text' => $term->sai_amount_type === 'fixed'
                ? 'السعي '.$this->formatRate((float) $term->fixed_sai_amount).' '.$term->fixed_sai_currency.' - يتحمله '.$label
                : 'السعي '.$this->formatRate($rate).'% - يتحملها '.$label,
        ];
    }

    public function policy(User $advertiser, string $purpose): array
    {
        $type = $this->advertiserType($advertiser);
        return [
            'configured' => false,
            'advertiser_type' => $type,
            'purpose' => $purpose,
            'payer' => $purpose === 'rent' ? 'tenant' : 'buyer',
            'payer_label' => $purpose === 'rent' ? 'المستأجر' : 'المشتري',
            'fixed_rate_percent' => $this->fixedRate($purpose),
            'broker_max_rate_percent' => $type === 'owner' ? null : $this->brokerMaxRate($purpose),
            'professional_platform_share_percent' => self::PLATFORM_BROKER_SHARE,
            'platform_terms_message' => 'للتطبيق نسبة مقدارها '.$this->formatRate(self::PLATFORM_BROKER_SHARE).'% من مبلغ السعي عند إتمام الصفقة.',
            'requires_configuration' => true,
            'amount_types' => $type === 'owner' ? ['percentage'] : ['percentage', 'fixed'],
        ];
    }

    public function managementData(Property $property, User $advertiser): array
    {
        $term = $this->currentTerm($property);
        $type = $this->advertiserType($advertiser);
        $purpose = (string) $property->purpose;

        if (! $term || $term->purpose !== $purpose || $term->advertiser_type !== $type) {
            return $this->policy($advertiser, $purpose);
        }

        return array_merge($this->policy($advertiser, $purpose), [
            'configured' => true,
            'term_id' => (int) $term->id,
            'version' => (int) $term->version,
            'advertiser_type' => $term->advertiser_type,
            'purpose' => $term->purpose,
            'source_mode' => $term->source_mode,
            'requested_broker_rate_percent' => $term->requested_broker_rate_percent !== null
                ? (float) $term->requested_broker_rate_percent
                : null,
            'sai_rate_percent' => (float) $term->sai_rate_percent,
            'sai_amount_type' => $term->sai_amount_type,
            'fixed_sai_amount' => $term->fixed_sai_amount,
            'fixed_sai_currency' => $term->fixed_sai_currency,
            'payer' => $term->payer,
            'payer_label' => $this->payerLabel($term->purpose, $term->payer),
            'calculation_basis' => $term->calculation_basis,
            'platform_share_percent' => (float) $term->platform_share_percent,
            'broker_share_percent' => (float) $term->broker_share_percent,
            'platform_terms_status' => $this->hasPlatformConsent($term) ? 'accepted' : $term->platform_terms_status,
            'requires_platform_terms_acceptance' => $term->source_mode === 'broker_custom'
                && ! $this->hasPlatformConsent($term),
            'platform_terms_message' => $term->source_mode === 'broker_custom'
                ? 'للتطبيق نسبة مقدارها 20% من مبلغ السعي عند إتمام الصفقة.'
                : null,
            'public_display_text' => $this->publicData($property)['display_text'] ?? null,
            'created_at' => optional($term->created_at)->toIso8601String(),
        ]);
    }

    public function currentTerm(Property $property): ?PropertySaiTerm
    {
        if (! $property->current_sai_term_id) {
            return null;
        }
        return PropertySaiTerm::query()->find($property->current_sai_term_id);
    }

    public function hasPlatformConsent(PropertySaiTerm $term): bool
    {
        if ($term->platform_terms_status === 'accepted') return true;
        return $term->platform_terms_status === 'pending'
            && DB::table('property_sai_attestations')->where('property_id', $term->property_id)
                ->where('sai_term_id', $term->id)->where('user_id', $term->created_by_user_id)->exists();
    }

    public function assertSettlementConsent(PropertySaiTerm $term): void
    {
        if ($term->platform_terms_status === 'pending' && ! $this->hasPlatformConsent($term)) {
            throw new ConflictHttpException('أكمل إقرار مستحق المنصة في إعلاناتي قبل تسجيل إتمام الصفقة. لا نغيّر شروط المحادثة المحفوظة.');
        }
    }

    public function calculateSaiAmount(PropertySaiTerm $term, float $basisAmount): array
    {
        if (! is_finite($basisAmount) || $basisAmount < 0) {
            throw ValidationException::withMessages(['amount' => ['Amount must not be negative.']]);
        }
        $total = $term->sai_amount_type === 'fixed'
            ? round((float) $term->fixed_sai_amount, 2)
            : round($basisAmount * ((float) $term->sai_rate_percent / 100), 2);
        $platform = round($total * ((float) $term->platform_share_percent / 100), 2);
        return [
            'total_sai' => $total,
            'platform_share' => $platform,
            'broker_share' => round($total - $platform, 2),
        ];
    }

    public function advertiserType(User $user): string
    {
        $profile = $user->verificationProfile();
        if ($profile?->isApproved()) {
            return match ($profile->type) {
                AccountVerificationProfile::TYPE_BROKER => 'broker',
                AccountVerificationProfile::TYPE_OFFICE => 'office',
                default => 'owner',
            };
        }

        // Historical local/test compatibility only. Current UAT advertisers
        // are required to have an approved verification profile.
        return $user->isBrokerAccount() ? 'broker' : 'owner';
    }

    public function fixedRate(string $purpose): float
    {
        return $purpose === 'rent' ? self::OWNER_RENT_RATE : self::OWNER_SALE_RATE;
    }

    private function fixedAmountLimit(Property $property): float
    {
        $basis = $property->purpose === 'rent'
            ? (float) ($property->monthly_rent ?? 0)
            : (float) $property->price;
        return round($basis * $this->brokerMaxRate((string) $property->purpose) / 100, 2);
    }

    public function brokerMaxRate(string $purpose): float
    {
        return $purpose === 'rent' ? self::BROKER_RENT_MAX : self::BROKER_SALE_MAX;
    }

    private function validatePayer(string $purpose, string $payer, bool $newConfiguration = false): void
    {
        // Old immutable terms remain readable/settleable. Every new version
        // follows the owner's October 13 customer-paid policy.
        $allowed = $newConfiguration
            ? [$purpose === 'rent' ? 'tenant' : 'buyer']
            : ($purpose === 'rent' ? ['landlord', 'tenant'] : ['seller', 'buyer']);
        if (! in_array($payer, $allowed, true)) {
            throw ValidationException::withMessages([
                'sai_payer' => [
                    $purpose === 'rent'
                        ? 'السعي في الشروط الجديدة يتحمله المستأجر.'
                        : 'السعي في الشروط الجديدة يتحمله المشتري.',
                ],
            ]);
        }
    }

    private function payerLabel(string $purpose, string $payer): string
    {
        return match ([$purpose, $payer]) {
            ['sale', 'seller'] => 'البائع',
            ['sale', 'buyer'] => 'المشتري',
            ['rent', 'landlord'] => 'المؤجر',
            ['rent', 'tenant'] => 'المستأجر',
            default => 'الطرف المحدد',
        };
    }

    private function formatRate(float $rate): string
    {
        return rtrim(rtrim(number_format($rate, 2, '.', ''), '0'), '.');
    }

    private function equivalent(PropertySaiTerm $current, array $candidate): bool
    {
        foreach ([
            'advertiser_type', 'purpose', 'source_mode', 'payer', 'calculation_basis', 'platform_terms_status', 'sai_amount_type', 'fixed_sai_currency',
        ] as $key) {
            if ((string) $current->{$key} !== (string) $candidate[$key]) return false;
        }
        foreach ([
            'requested_broker_rate_percent', 'sai_rate_percent', 'platform_share_percent', 'broker_share_percent', 'fixed_sai_amount',
        ] as $key) {
            $a = $current->{$key};
            $b = $candidate[$key];
            if ($a === null || $b === null) {
                if ($a !== null || $b !== null) return false;
                continue;
            }
            if (abs((float) $a - (float) $b) > 0.001) return false;
        }
        return true;
    }
}
