<?php

namespace App\Services;

use App\Models\MessageThread;
use App\Models\PropertyAgreement;
use App\Models\PropertySaiTerm;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertySaiSettlementService
{
    private const RENT_CADENCE_MONTHS = [
        'monthly' => 1,
        'quarterly' => 3,
        'semiannual' => 6,
        'annual' => 12,
    ];

    public function __construct(private readonly PropertySaiService $sai) {}

    /**
     * Persist the immutable accounting snapshot for an agreement that has
     * actually been accepted by both parties. No payment is collected here.
     */
    public function settleAcceptedAgreement(PropertyAgreement $agreement): ?object
    {
        if ($agreement->status !== 'accepted') {
            return null;
        }

        return DB::transaction(function () use ($agreement): ?object {
            $lockedAgreement = PropertyAgreement::query()
                ->whereKey($agreement->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($lockedAgreement->status !== 'accepted') {
                return null;
            }

            $existing = DB::table('property_sai_settlements')
                ->where('property_agreement_id', $lockedAgreement->id)
                ->first();
            if ($existing) {
                return $existing;
            }

            $termId = $lockedAgreement->sai_term_id;
            if (! $termId) {
                // Compatibility for draft agreements created before the
                // agreement-level Sai snapshot column existed. The thread is
                // still the authoritative frozen customer-journey snapshot.
                $termId = MessageThread::query()
                    ->whereKey($lockedAgreement->message_thread_id)
                    ->lockForUpdate()
                    ->value('sai_term_id');
            }

            // Truly legacy journeys may predate Sai entirely. Never invent a
            // historical financial obligation for them.
            if (! $termId) {
                return null;
            }

            $term = PropertySaiTerm::query()->find($termId);
            if (! $term) {
                throw new ConflictHttpException('تعذر تثبيت السعي لأن نسخة شروط السعي المجمدة غير موجودة.');
            }

            if ((int) $term->property_id !== (int) $lockedAgreement->property_id
                || $term->purpose !== $lockedAgreement->transaction_type) {
                throw new ConflictHttpException('نسخة شروط السعي المجمدة لا تطابق العقار أو نوع الاتفاق.');
            }

            $revision = DB::table('property_agreement_revisions')
                ->where('property_agreement_id', $lockedAgreement->id)
                ->orderByDesc('revision_number')
                ->lockForUpdate()
                ->first();
            if (! $revision) {
                throw new ConflictHttpException('لا يمكن حساب السعي بدون نسخة اتفاق نهائية.');
            }

            $basisAmount = $this->basisAmount(
                $lockedAgreement->transaction_type,
                (float) $revision->agreed_amount,
                $revision->rent_cadence,
            );
            $amounts = $this->sai->calculateSaiAmount($term, $basisAmount);

            $now = now();
            DB::table('property_sai_settlements')->insert([
                'property_agreement_id' => (int) $lockedAgreement->id,
                'property_agreement_revision_id' => (int) $revision->id,
                'property_id' => (int) $lockedAgreement->property_id,
                'message_thread_id' => (int) $lockedAgreement->message_thread_id,
                'sai_term_id' => (int) $term->id,
                'transaction_type' => $lockedAgreement->transaction_type,
                'payer' => $term->payer,
                'calculation_basis' => $term->calculation_basis,
                'basis_amount' => $basisAmount,
                'currency' => $revision->currency,
                'sai_rate_percent' => (float) $term->sai_rate_percent,
                'total_sai_amount' => $amounts['total_sai'],
                'platform_share_percent' => (float) $term->platform_share_percent,
                'platform_share_amount' => $amounts['platform_share'],
                'broker_share_percent' => (float) $term->broker_share_percent,
                'broker_share_amount' => $amounts['broker_share'],
                'settled_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            return DB::table('property_sai_settlements')
                ->where('property_agreement_id', $lockedAgreement->id)
                ->first();
        });
    }

    public function basisAmount(string $transactionType, float $agreedAmount, ?string $rentCadence): float
    {
        if ($agreedAmount <= 0) {
            throw new ConflictHttpException('قيمة الاتفاق النهائية يجب أن تكون أكبر من صفر قبل حساب السعي.');
        }

        if ($transactionType === 'sale') {
            return round($agreedAmount, 2);
        }

        if ($transactionType !== 'rent') {
            throw new ConflictHttpException('نوع الاتفاق غير مدعوم لحساب السعي.');
        }

        $months = self::RENT_CADENCE_MONTHS[$rentCadence ?? ''] ?? null;
        if (! $months) {
            throw new ConflictHttpException('دورية الإيجار غير صالحة لحساب قيمة إيجار شهر واحد.');
        }

        return round($agreedAmount / $months, 2);
    }
}
