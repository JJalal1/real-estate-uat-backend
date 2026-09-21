<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPayment;
use App\Models\PropertyPaymentMethod;
use App\Models\PropertyPlatformReceivable;
use App\Models\User;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class CompletePropertyFinancialService extends PropertyFinancialService
{
    public function __construct(
        PropertySaiSettlementService $saiSettlements,
        AuditLogService $audit,
        private readonly UserNotificationService $completeNotifications,
    ) {
        parent::__construct($saiSettlements, $audit, $completeNotifications);
    }

    public function paymentMethods(float $amount, string $currency, ?string $mode = null): array
    {
        $rows = parent::paymentMethods($amount, $currency);
        $methods = PropertyPaymentMethod::query()->whereIn('id', collect($rows)->pluck('id'))->get()->keyBy('id');

        return collect($rows)->map(function (array $row) use ($methods, $mode): array {
            $method = $methods->get($row['id']);
            $row['allows_full_payment'] = (bool) ($method?->allows_full_payment ?? true);
            $row['allows_sai_only'] = (bool) ($method?->allows_sai_only ?? true);
            if (($row['available'] ?? false) && $mode === 'platform_full' && ! $row['allows_full_payment']) {
                $row['available'] = false;
                $row['unavailable_reason'] = 'هذه الوسيلة غير مفعلة للدفع الكامل للصفقة.';
            }
            if (($row['available'] ?? false) && in_array($mode, ['platform_sai_only','platform_receivable'], true) && ! $row['allows_sai_only']) {
                $row['available'] = false;
                $row['unavailable_reason'] = 'هذه الوسيلة غير مفعلة لسداد السعي أو مستحقات المنصة.';
            }
            return $row;
        })->values()->all();
    }

    public function createPayment(PropertyDealFinancialTerm $term, User $actor, string $mode, PropertyPaymentMethod $method, Request $request): PropertyPayment
    {
        if ($mode === 'platform_full' && ! $method->allows_full_payment) {
            throw new ConflictHttpException('طريقة الدفع المختارة غير متاحة للدفع الكامل لهذه الصفقة.');
        }
        if (in_array($mode, ['platform_sai_only','platform_receivable'], true) && ! $method->allows_sai_only) {
            throw new ConflictHttpException('طريقة الدفع المختارة غير متاحة لسداد السعي أو مستحقات المنصة.');
        }
        return parent::createPayment($term, $actor, $mode, $method, $request);
    }

    public function hasOverdueReceivable(int $advertiserUserId): bool
    {
        $this->activateOverdueHold($advertiserUserId);
        return parent::hasOverdueReceivable($advertiserUserId);
    }

    public function financialSummaryFor(User $user): array
    {
        $this->activateOverdueHold((int) $user->id);
        return parent::financialSummaryFor($user);
    }

    private function activateOverdueHold(int $advertiserUserId): void
    {
        $overdue = PropertyPlatformReceivable::query()
            ->where('advertiser_user_id', $advertiserUserId)
            ->whereIn('status', ['open','under_review','overdue','disputed'])
            ->whereColumn('amount_paid','<','amount_total')
            ->where('due_at','<=',now())
            ->get();
        if ($overdue->isEmpty()) return;

        $transitioned = PropertyPlatformReceivable::query()
            ->whereIn('id', $overdue->pluck('id'))
            ->whereIn('status', ['open','under_review'])
            ->update(['status'=>'overdue','updated_at'=>now()]);
        $hidden = Property::query()->withoutGlobalScopes()
            ->where('user_id',$advertiserUserId)
            ->where('status','published')
            ->whereNull('financial_hold_at')
            ->update([
                'financial_hold_at'=>now(),
                'financial_hold_reason'=>'platform_receivable_overdue',
                'updated_at'=>now(),
            ]);
        if ($transitioned > 0 || $hidden > 0) {
            $amount = round((float)$overdue->sum(fn($r)=>max(0,(float)$r->amount_total-(float)$r->amount_paid)),2);
            $this->completeNotifications->create(
                $advertiserUserId,
                'financial_hold_started',
                'تم تفعيل القيد المالي',
                'انتهت مهلة 24 ساعة وما زال مستحق المنصة غير مسدد. أُخفيت الإعلانات المنشورة مؤقتًا حتى تأكيد السداد.',
                'property_platform_receivable',
                (int)$overdue->first()->id,
                ['amount'=>$amount,'currency'=>$overdue->first()->currency,'destination'=>'financial_account'],
            );
        }
    }
}
