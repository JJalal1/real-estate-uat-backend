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
    ): PropertySaiTerm {
        if ((int) $property->user_id !== (int) $actor->id) {
            abort(403, 'Only the listing advertiser can configure sai terms.');
        }

        return DB::transaction(function () use ($actor, $property, $payer, $brokerRate, $platformTermsDecision, $request): PropertySaiTerm {
            $locked = Property::query()->whereKey($property->id)->lockForUpdate()->firstOrFail();
            if ($locked->status === 'published'
                || in_array($locked->review_status, ['submitted', 'under_review', 'rejected_blocked'], true)) {
                throw new ConflictHttpException('عدّل الإعلان أولاً ليعود إلى المسودة، ثم أكد شروط السعي وأرسله للمراجعة من جديد.');
            }

            $advertiserType = $this->advertiserType($actor);
            $purpose = (string) $locked->purpose;
            $this->validatePayer($purpose, $payer);

            $sourceMode = 'owner_fixed';
            $requestedRate = null;
            $effectiveRate = $this->fixedRate($purpose);
            $platformShare = 100.0;
            $brokerShare = 0.0;
            $termsStatus = 'not_required';
            $acceptedAt = null;
            $rejectedAt = null;

            if ($advertiserType === 'owner') {
                if ($brokerRate !== null) {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => ['المالك لا يستطيع تحديد أو تغيير نسبة السعي. يحدد فقط من يتحمل السعي.'],
                    ]);
                }
            } else {
                if ($brokerRate === null) {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => ['حدد نسبة السعي للدلال/المكتب من صفر وحتى الحد المسموح.'],
                    ]);
                }

                $max = $this->brokerMaxRate($purpose);
                if ($brokerRate < 0 || $brokerRate > $max) {
                    throw ValidationException::withMessages([
                        'broker_sai_rate_percent' => [
                            $purpose === 'sale'
                                ? 'السعي في البيع يجب أن يكون بين 0% و5%.'
                                : 'السعي في الإيجار يجب أن يكون بين 0% و100% من إيجار الشهر الأول.',
                        ],
                    ]);
                }

                $requestedRate = round($brokerRate, 2);
                if ($requestedRate > 0) {
                    $sourceMode = 'broker_custom';
                    $effectiveRate = $requestedRate;
                    $platformShare = self::PLATFORM_BROKER_SHARE;
                    $brokerShare = self::BROKER_NET_SHARE;

                    if (! in_array($platformTermsDecision, ['accept', 'reject'], true)) {
                        throw ValidationException::withMessages([
                            'platform_terms_decision' => ['يجب قبول أو رفض شرط نسبة التطبيق قبل المتابعة.'],
                        ]);
                    }
                    $termsStatus = $platformTermsDecision === 'accept' ? 'accepted' : 'rejected';
                    $acceptedAt = $termsStatus === 'accepted' ? now() : null;
                    $rejectedAt = $termsStatus === 'rejected' ? now() : null;
                } else {
                    // 0% means no broker/office sai. It never means a free
                    // transaction: the fixed platform sai becomes effective.
                    $sourceMode = 'platform_fallback';
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
                || abs((float) $term->sai_rate_percent - $fixed) > 0.001
                || (float) $term->platform_share_percent !== 100.0
                || (float) $term->broker_share_percent !== 0.0) {
                throw new ConflictHttpException('شروط سعي المالك غير مطابقة للسياسة المعتمدة. أعد تحديد من يتحمل السعي.');
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
                || $term->platform_terms_status !== 'accepted') {
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
            'rate_percent' => $rate,
            'payer' => $term->payer,
            'payer_label' => $label,
            'calculation_basis' => $term->calculation_basis,
            'display_text' => 'السعي '.$this->formatRate($rate).'% - يتحملها '.$label,
        ];
    }

    public function managementData(Property $property, User $advertiser): array
    {
        $term = $this->currentTerm($property);
        $type = $this->advertiserType($advertiser);
        $purpose = (string) $property->purpose;

        if (! $term || $term->purpose !== $purpose || $term->advertiser_type !== $type) {
            return [
                'configured' => false,
                'advertiser_type' => $type,
                'fixed_rate_percent' => $this->fixedRate($purpose),
                'broker_max_rate_percent' => $type === 'owner' ? null : $this->brokerMaxRate($purpose),
                'requires_configuration' => true,
            ];
        }

        return [
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
            'payer' => $term->payer,
            'payer_label' => $this->payerLabel($term->purpose, $term->payer),
            'calculation_basis' => $term->calculation_basis,
            'platform_share_percent' => (float) $term->platform_share_percent,
            'broker_share_percent' => (float) $term->broker_share_percent,
            'platform_terms_status' => $term->platform_terms_status,
            'requires_platform_terms_acceptance' => $term->source_mode === 'broker_custom'
                && $term->platform_terms_status !== 'accepted',
            'platform_terms_message' => $term->source_mode === 'broker_custom'
                ? 'للتطبيق نسبة مقدارها 20% من مبلغ السعي عند إتمام الصفقة.'
                : null,
            'public_display_text' => $this->publicData($property)['display_text'] ?? null,
            'created_at' => optional($term->created_at)->toIso8601String(),
        ];
    }

    public function currentTerm(Property $property): ?PropertySaiTerm
    {
        if (! $property->current_sai_term_id) {
            return null;
        }
        return PropertySaiTerm::query()->find($property->current_sai_term_id);
    }

    public function calculateSaiAmount(PropertySaiTerm $term, float $basisAmount): array
    {
        if ($basisAmount < 0) {
            throw ValidationException::withMessages(['amount' => ['Amount must not be negative.']]);
        }
        $total = round($basisAmount * ((float) $term->sai_rate_percent / 100), 2);
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

    public function brokerMaxRate(string $purpose): float
    {
        return $purpose === 'rent' ? self::BROKER_RENT_MAX : self::BROKER_SALE_MAX;
    }

    private function validatePayer(string $purpose, string $payer): void
    {
        $allowed = $purpose === 'rent' ? ['landlord', 'tenant'] : ['seller', 'buyer'];
        if (! in_array($payer, $allowed, true)) {
            throw ValidationException::withMessages([
                'sai_payer' => [
                    $purpose === 'rent'
                        ? 'حدد من يتحمل السعي: المؤجر أو المستأجر.'
                        : 'حدد من يتحمل السعي: البائع أو المشتري.',
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
            'advertiser_type', 'purpose', 'source_mode', 'payer', 'calculation_basis', 'platform_terms_status',
        ] as $key) {
            if ((string) $current->{$key} !== (string) $candidate[$key]) return false;
        }
        foreach ([
            'requested_broker_rate_percent', 'sai_rate_percent', 'platform_share_percent', 'broker_share_percent',
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
