<?php

namespace App\Services;

use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPayment;
use App\Models\PropertyPaymentMethod;
use App\Models\User;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class CompletePropertyFinancialService extends PropertyFinancialService
{
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
}
