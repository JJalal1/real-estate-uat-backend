<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyAgreement;
use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPayment;
use App\Models\PropertyPaymentMethod;
use App\Models\PropertyPlatformReceivable;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertyFinancialService
{
    public const SAI_ATTESTATION_TEXT = 'أقسم بالله أنني إذا تمت الصفقة عن طريق المنصة فسأقوم بسداد مستحقات المنصة من السعي حسب الشروط التي وافقت عليها عند نشر الإعلان.';

    public function __construct(
        private readonly PropertySaiSettlementService $saiSettlements,
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
    ) {}

    public function freezeAcceptedAgreement(PropertyAgreement $agreement): ?PropertyDealFinancialTerm
    {
        if ($agreement->status !== 'accepted') return null;

        $settlement = $this->saiSettlements->settleAcceptedAgreement($agreement);
        if (! $settlement) return null;

        return DB::transaction(function () use ($agreement, $settlement): PropertyDealFinancialTerm {
            $locked = PropertyAgreement::query()->whereKey($agreement->id)->lockForUpdate()->firstOrFail();
            $existing = PropertyDealFinancialTerm::query()->where('property_agreement_id', $locked->id)->first();
            if ($existing) return $existing;

            $revision = DB::table('property_agreement_revisions')
                ->where('property_agreement_id', $locked->id)
                ->orderByDesc('revision_number')->lockForUpdate()->first();
            if (! $revision) throw new ConflictHttpException('لا توجد نسخة اتفاق نهائية لتجميد الشروط المالية.');

            $property = Property::query()->findOrFail($locked->property_id);
            $term = DB::table('property_sai_terms')->where('id', $settlement->sai_term_id)->first();
            if (! $term) throw new ConflictHttpException('نسخة شروط السعي المجمدة غير موجودة.');

            $monthly = null;
            $rentalTermMonths = null;
            $advanceMonths = null;
            $baseAmount = round((float) $revision->agreed_amount, 2);

            if ($locked->transaction_type === 'rent') {
                $monthly = isset($revision->monthly_rent) && (float) $revision->monthly_rent > 0
                    ? round((float) $revision->monthly_rent, 2)
                    : round((float) $settlement->basis_amount, 2);
                $rentalTermMonths = isset($revision->rental_term_months) && (int) $revision->rental_term_months > 0
                    ? (int) $revision->rental_term_months
                    : ($property->rental_term_months ? (int) $property->rental_term_months : null);
                $advanceMonths = isset($revision->advance_months) && (int) $revision->advance_months > 0
                    ? (int) $revision->advance_months
                    : ($property->advance_months ? (int) $property->advance_months : null);
                if (isset($revision->monthly_rent) && (float) $revision->monthly_rent > 0 && $advanceMonths) {
                    $baseAmount = round($monthly * $advanceMonths, 2);
                }
            }

            return PropertyDealFinancialTerm::query()->create([
                'property_agreement_id'=>$locked->id,
                'property_agreement_revision_id'=>$revision->id,
                'property_sai_settlement_id'=>$settlement->id,
                'property_id'=>$locked->property_id,
                'buyer_user_id'=>$locked->requester_user_id,
                'advertiser_user_id'=>$locked->advertiser_user_id,
                'transaction_type'=>$locked->transaction_type,
                'advertiser_type'=>$term->advertiser_type,
                'currency'=>strtoupper((string) $revision->currency),
                'base_amount'=>$baseAmount,
                'monthly_basis_amount'=>$monthly,
                'rental_term_months'=>$rentalTermMonths,
                'advance_months'=>$advanceMonths,
                'sai_payer'=>$settlement->payer,
                'sai_total_amount'=>(float) $settlement->total_sai_amount,
                'platform_share_amount'=>(float) $settlement->platform_share_amount,
                'advertiser_sai_share_amount'=>(float) $settlement->broker_share_amount,
                'price_display_mode'=>$property->price_display_mode,
                'snapshot'=>[
                    'property_title'=>$property->title,
                    'agreement_reference'=>$locked->reference,
                    'sai_term_id'=>(int) $settlement->sai_term_id,
                    'sai_rate_percent'=>(float) $settlement->sai_rate_percent,
                    'calculation_basis'=>$settlement->calculation_basis,
                ],
                'frozen_at'=>now(),
            ]);
        });
    }

    public function ensureFinancialTerm(PropertyAgreement $agreement): PropertyDealFinancialTerm
    {
        $term = PropertyDealFinancialTerm::query()->where('property_agreement_id', $agreement->id)->first();
        if ($term) return $term;
        $term = $this->freezeAcceptedAgreement($agreement);
        if (! $term) throw new ConflictHttpException('يجب اعتماد الاتفاق من الطرفين قبل الدفع.');
        return $term;
    }

    public function requiredAmount(PropertyDealFinancialTerm $term, string $mode, User $actor): float
    {
        $buyerPaysSai = in_array($term->sai_payer, ['buyer','tenant'], true);
        if ($mode === 'platform_full') {
            abort_unless((int) $actor->id === (int) $term->buyer_user_id, 403);
            return round((float) $term->base_amount + ($buyerPaysSai ? (float) $term->sai_total_amount : 0), 2);
        }
        if ($mode === 'platform_sai_only') {
            if ($buyerPaysSai) {
                abort_unless((int) $actor->id === (int) $term->buyer_user_id, 403);
                return round((float) $term->sai_total_amount, 2);
            }
            abort_unless((int) $actor->id === (int) $term->advertiser_user_id, 403);
            return round((float) $term->platform_share_amount, 2);
        }
        if ($mode === 'platform_receivable') {
            abort_unless((int) $actor->id === (int) $term->advertiser_user_id, 403);
            $receivable = PropertyPlatformReceivable::query()->where('deal_financial_term_id', $term->id)->first();
            if (! $receivable || $receivable->status === 'paid') {
                throw new ConflictHttpException('لا يوجد مستحق مفتوح للمنصة لهذه الصفقة.');
            }
            return round(max(0, (float) $receivable->amount_total - (float) $receivable->amount_paid), 2);
        }
        throw ValidationException::withMessages(['mode'=>['طريقة التسوية غير مدعومة.']]);
    }

    public function paymentMethods(float $amount, string $currency): array
    {
        return PropertyPaymentMethod::query()->where('is_enabled', true)->orderBy('sort_order')->get()
            ->map(function (PropertyPaymentMethod $method) use ($amount, $currency): array {
                $reason = null;
                if (strtoupper($method->currency) !== strtoupper($currency)) $reason = 'هذه الوسيلة لا تدعم عملة الصفقة.';
                elseif ($method->min_amount !== null && $amount < (float) $method->min_amount) $reason = 'المبلغ أقل من الحد الأدنى لهذه الوسيلة.';
                elseif ($method->max_amount !== null && $amount > (float) $method->max_amount) $reason = 'المبلغ أكبر من الحد الأعلى لهذه الوسيلة.';
                return [
                    'id'=>$method->id,'key'=>$method->key,'name_ar'=>$method->name_ar,'asset_key'=>$method->asset_key,
                    'beneficiary_name'=>$method->beneficiary_name,'destination_label'=>$method->destination_label,
                    'destination_value'=>$method->destination_value,'currency'=>$method->currency,
                    'instructions_ar'=>$method->instructions_ar,'requires_sender_phone'=>$method->requires_sender_phone,
                    'requires_provider_reference'=>$method->requires_provider_reference,'available'=>$reason === null,
                    'unavailable_reason'=>$reason,
                ];
            })->values()->all();
    }

    public function createPayment(PropertyDealFinancialTerm $term, User $actor, string $mode, PropertyPaymentMethod $method, Request $request): PropertyPayment
    {
        $amount = $this->requiredAmount($term, $mode, $actor);
        if ($amount <= 0) throw new ConflictHttpException('لا يوجد مبلغ مستحق للدفع بهذه الطريقة.');
        if (! $method->is_enabled) throw new ConflictHttpException('طريقة الدفع غير متاحة حاليًا.');
        if (strtoupper($method->currency) !== strtoupper($term->currency)) throw new ConflictHttpException('طريقة الدفع لا تدعم عملة الصفقة.');
        if ($method->min_amount !== null && $amount < (float) $method->min_amount) throw new ConflictHttpException('المبلغ أقل من الحد الأدنى لطريقة الدفع.');
        if ($method->max_amount !== null && $amount > (float) $method->max_amount) throw new ConflictHttpException('المبلغ أكبر من الحد الأعلى لطريقة الدفع.');

        return DB::transaction(function () use ($term, $actor, $mode, $method, $amount, $request): PropertyPayment {
            $active = PropertyPayment::query()->where('deal_financial_term_id', $term->id)
                ->where('payer_user_id', $actor->id)->where('mode', $mode)
                ->whereIn('status', ['waiting_payment','proof_submitted','under_review','correction_required'])->latest('id')->first();
            if ($active) return $active;

            $payment = PropertyPayment::query()->create([
                'reference'=>$this->reference('PAY'),'deal_financial_term_id'=>$term->id,'property_id'=>$term->property_id,
                'payer_user_id'=>$actor->id,'advertiser_user_id'=>$term->advertiser_user_id,'payment_method_id'=>$method->id,
                'mode'=>$mode,'status'=>'waiting_payment','required_amount'=>$amount,'currency'=>$term->currency,
            ]);
            $this->audit->record($actor, 'finance.payment_created', $payment, [
                'mode'=>$mode,'amount'=>$amount,'currency'=>$term->currency,'payment_method'=>$method->key,
            ], $request, $term->advertiser_user_id);
            return $payment->fresh('method');
        });
    }

    public function submitProof(PropertyPayment $payment, User $actor, array $proof, Request $request): PropertyPayment
    {
        abort_unless((int) $payment->payer_user_id === (int) $actor->id, 403);
        if (! in_array($payment->status, ['waiting_payment','correction_required'], true)) {
            throw new ConflictHttpException('لا يمكن رفع إثبات لهذه العملية في حالتها الحالية.');
        }

        return DB::transaction(function () use ($payment, $actor, $proof, $request): PropertyPayment {
            $locked = PropertyPayment::query()->whereKey($payment->id)->lockForUpdate()->firstOrFail();
            if (! in_array($locked->status, ['waiting_payment','correction_required'], true)) throw new ConflictHttpException('تم تحديث حالة عملية الدفع.');

            $providerReference = trim((string) ($proof['provider_reference'] ?? '')) ?: null;
            if ($providerReference !== null) {
                $duplicate = PropertyPayment::query()->where('payment_method_id', $locked->payment_method_id)
                    ->where('provider_reference', $providerReference)->whereKeyNot($locked->id)->exists();
                if ($duplicate) throw ValidationException::withMessages(['provider_reference'=>['رقم العملية مستخدم في عملية دفع أخرى.']]);
            }

            $locked->forceFill([
                'status'=>'proof_submitted','provider_reference'=>$providerReference,
                'sender_name'=>trim((string) ($proof['sender_name'] ?? '')) ?: null,
                'sender_phone'=>trim((string) ($proof['sender_phone'] ?? '')) ?: null,
                'proof_path'=>$proof['proof_path'],'proof_original_name'=>$proof['proof_original_name'],
                'proof_mime_type'=>$proof['proof_mime_type'],'proof_size_bytes'=>$proof['proof_size_bytes'],
                'submitted_at'=>now(),'reviewed_at'=>null,'reviewed_by_user_id'=>null,'reviewed_by_name_snapshot'=>null,'review_note'=>null,
            ])->save();
            $this->audit->record($actor, 'finance.payment_proof_submitted', $locked, [
                'amount'=>(float) $locked->required_amount,'currency'=>$locked->currency,'has_provider_reference'=>$providerReference !== null,
            ], $request, $locked->advertiser_user_id);
            return $locked->fresh('method');
        });
    }

    public function reviewPayment(PropertyPayment $payment, User $reviewer, string $decision, ?string $note, Request $request): PropertyPayment
    {
        if (! $reviewer->hasPermission('payments.review')) abort(403);
        if (! in_array($decision, ['confirm','correction','reject'], true)) {
            throw ValidationException::withMessages(['decision'=>['قرار المراجعة غير مدعوم.']]);
        }

        return DB::transaction(function () use ($payment, $reviewer, $decision, $note, $request): PropertyPayment {
            $locked = PropertyPayment::query()->whereKey($payment->id)->lockForUpdate()->firstOrFail();
            if (! in_array($locked->status, ['proof_submitted','under_review'], true)) throw new ConflictHttpException('عملية الدفع ليست جاهزة للمراجعة.');
            $next = match ($decision) { 'confirm'=>'confirmed', 'correction'=>'correction_required', default=>'rejected' };
            $locked->forceFill([
                'status'=>$next,'reviewed_by_user_id'=>$reviewer->id,'reviewed_by_name_snapshot'=>$reviewer->name,
                'review_note'=>$note,'reviewed_at'=>now(),'confirmed_at'=>$next === 'confirmed' ? now() : null,
            ])->save();

            if ($next === 'confirmed') $this->postConfirmedPayment($locked, $reviewer);

            $this->audit->record($reviewer, 'finance.payment_reviewed', $locked, ['decision'=>$decision,'status'=>$next], $request, $locked->payer_user_id);
            $title = $next === 'confirmed' ? 'تم تأكيد الدفع' : ($next === 'correction_required' ? 'يحتاج إثبات الدفع إلى تصحيح' : 'تم رفض إثبات الدفع');
            $body = $next === 'confirmed'
                ? 'تم التحقق من عملية الدفع '.$locked->reference.'.'
                : (trim((string) $note) !== '' ? (string) $note : 'راجع عملية الدفع وأعد المحاولة عند الحاجة.');
            $this->notifications->create((int) $locked->payer_user_id, 'property_payment_review', $title, $body, 'property_payment', $locked->id, ['payment_id'=>$locked->id,'status'=>$next]);
            return $locked->fresh('method');
        });
    }

    public function confirmDirectPayment(PropertyDealFinancialTerm $term, User $actor, string $decision, ?string $note, Request $request): array
    {
        abort_unless(in_array((int) $actor->id, [(int) $term->buyer_user_id,(int) $term->advertiser_user_id], true), 403);
        if (! in_array($decision, ['confirmed','disputed'], true)) throw ValidationException::withMessages(['decision'=>['اختر تأكيد الدفع أو الاعتراض.']]);
        $role = (int) $actor->id === (int) $term->buyer_user_id ? 'buyer' : 'advertiser';
        $buyerPaysSai = in_array($term->sai_payer, ['buyer','tenant'], true);
        $directAmount = round((float) $term->base_amount + ($buyerPaysSai ? (float) $term->sai_total_amount : 0), 2);

        return DB::transaction(function () use ($term, $actor, $decision, $note, $request, $role, $directAmount): array {
            DB::table('property_manual_payment_confirmations')->updateOrInsert(
                ['deal_financial_term_id'=>$term->id,'user_id'=>$actor->id],
                ['party_role'=>$role,'decision'=>$decision,'amount'=>$directAmount,'currency'=>$term->currency,'note'=>$note,'confirmed_at'=>now(),'created_at'=>now(),'updated_at'=>now()],
            );
            $this->audit->record($actor, 'finance.direct_payment_'.$decision, $term, ['party_role'=>$role,'amount'=>$directAmount], $request, $role === 'buyer' ? $term->advertiser_user_id : $term->buyer_user_id);

            if ($decision === 'disputed') {
                DB::table('property_financial_disputes')->insertOrIgnore([
                    'reference'=>$this->reference('DSP'),'deal_financial_term_id'=>$term->id,'opened_by_user_id'=>$actor->id,
                    'status'=>'open','reason'=>trim((string) $note) ?: 'اعتراض على تأكيد الدفع المباشر.','created_at'=>now(),'updated_at'=>now(),
                ]);
                return ['completed'=>false,'disputed'=>true,'receivable'=>null];
            }

            $rows = DB::table('property_manual_payment_confirmations')->where('deal_financial_term_id', $term->id)->get();
            $buyerOk = $rows->contains(fn ($r) => $r->party_role === 'buyer' && $r->decision === 'confirmed');
            $advertiserOk = $rows->contains(fn ($r) => $r->party_role === 'advertiser' && $r->decision === 'confirmed');
            if (! $buyerOk || ! $advertiserOk) return ['completed'=>false,'disputed'=>false,'receivable'=>null];

            $receivable = PropertyPlatformReceivable::query()->where('deal_financial_term_id', $term->id)->first();
            if (! $receivable && (float) $term->platform_share_amount > 0) {
                $receivable = PropertyPlatformReceivable::query()->create([
                    'reference'=>$this->reference('DUE'),'deal_financial_term_id'=>$term->id,'property_id'=>$term->property_id,
                    'advertiser_user_id'=>$term->advertiser_user_id,'amount_total'=>$term->platform_share_amount,'amount_paid'=>0,
                    'currency'=>$term->currency,'status'=>'open','confirmed_direct_at'=>now(),'due_at'=>now()->addHours(24),
                ]);
                DB::table('property_financial_holds')->insert([
                    'user_id'=>$term->advertiser_user_id,'reason'=>'platform_receivable_open','source_type'=>'property_platform_receivable',
                    'source_id'=>$receivable->id,'started_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
                ]);
                $this->postLedger('platform_receivable_created','property_platform_receivable',$receivable->id,null,'استحقاق حصة المنصة من صفقة مباشرة',[
                    ['account_code'=>'advertiser_receivable','user_id'=>$term->advertiser_user_id,'direction'=>'debit','amount'=>(float) $term->platform_share_amount,'currency'=>$term->currency],
                    ['account_code'=>'platform_revenue','user_id'=>null,'direction'=>'credit','amount'=>(float) $term->platform_share_amount,'currency'=>$term->currency],
                ]);
                $this->notifications->create((int) $term->advertiser_user_id, 'platform_receivable_created', 'مستحق للمنصة', 'تم تأكيد الصفقة المباشرة. لديك 24 ساعة لتسديد مستحق المنصة.', 'property_platform_receivable', $receivable->id, ['receivable_id'=>$receivable->id,'due_at'=>$receivable->due_at?->toIso8601String()]);
            }
            return ['completed'=>true,'disputed'=>false,'receivable'=>$receivable];
        });
    }

    public function hasOpenReceivable(int $advertiserUserId): bool
    {
        return PropertyPlatformReceivable::query()->where('advertiser_user_id', $advertiserUserId)
            ->whereIn('status', ['open','under_review','overdue','disputed'])->whereColumn('amount_paid','<','amount_total')->exists();
    }

    public function hasOverdueReceivable(int $advertiserUserId): bool
    {
        return PropertyPlatformReceivable::query()->where('advertiser_user_id', $advertiserUserId)
            ->whereIn('status', ['open','under_review','overdue','disputed'])->whereColumn('amount_paid','<','amount_total')->where('due_at','<=',now())->exists();
    }

    public function financialSummaryFor(User $user): array
    {
        $receivables = PropertyPlatformReceivable::query()->where('advertiser_user_id', $user->id)->get();
        $payouts = DB::table('property_payouts')->where('advertiser_user_id', $user->id)->get();
        return [
            'open_platform_due'=>round((float) $receivables->whereIn('status',['open','under_review','overdue','disputed'])->sum(fn($r)=>max(0,(float)$r->amount_total-(float)$r->amount_paid)),2),
            'overdue_platform_due'=>round((float) $receivables->filter(fn($r)=>in_array($r->status,['open','under_review','overdue','disputed'],true) && $r->due_at && now()->gte($r->due_at))->sum(fn($r)=>max(0,(float)$r->amount_total-(float)$r->amount_paid)),2),
            'pending_payouts'=>round((float) $payouts->where('status','pending')->sum('amount'),2),
            'paid_payouts'=>round((float) $payouts->where('status','paid')->sum('amount'),2),
            'listing_creation_blocked'=>$this->hasOpenReceivable((int) $user->id),
            'published_listings_hidden'=>$this->hasOverdueReceivable((int) $user->id),
        ];
    }

    public function attestSai(Property $property, User $user, Request $request): void
    {
        abort_unless((int) $property->user_id === (int) $user->id, 403);
        abort_unless($property->status === 'published' && $property->current_sai_term_id, 409, 'يظهر الإقرار بعد نشر إعلان بشروط سعي معتمدة.');
        $term = DB::table('property_sai_terms')->where('id', $property->current_sai_term_id)->first();
        abort_unless($term, 409);
        DB::table('property_sai_attestations')->updateOrInsert(
            ['property_id'=>$property->id,'sai_term_id'=>$term->id],
            ['user_id'=>$user->id,'terms_version'=>$term->version,'text_snapshot'=>self::SAI_ATTESTATION_TEXT,
             'ip_address'=>$request->ip(),'user_agent'=>substr((string)$request->userAgent(),0,500),'accepted_at'=>now(),'created_at'=>now(),'updated_at'=>now()],
        );
        $this->audit->record($user, 'listing.sai_attested', $property, ['sai_term_id'=>(int)$term->id,'terms_version'=>(int)$term->version], $request, $user->id);
    }

    public function pendingSaiAttestation(Property $property): bool
    {
        if ($property->status !== 'published' || ! $property->current_sai_term_id) return false;
        return ! DB::table('property_sai_attestations')->where('property_id',$property->id)->where('sai_term_id',$property->current_sai_term_id)->exists();
    }

    private function postConfirmedPayment(PropertyPayment $payment, User $reviewer): void
    {
        if (DB::table('property_payment_allocations')->where('property_payment_id', $payment->id)->exists()) return;
        $term = PropertyDealFinancialTerm::query()->findOrFail($payment->deal_financial_term_id);
        $platform = (float) $term->platform_share_amount;
        $brokerShare = (float) $term->advertiser_sai_share_amount;
        $buyerPaysSai = in_array($term->sai_payer, ['buyer','tenant'], true);
        $payout = 0.0;

        if ($payment->mode === 'platform_full') {
            $payout = round((float) $payment->required_amount - $platform, 2);
            if ($platform > 0) $this->allocation($payment, 'platform_revenue', null, $platform);
            $principalAllocation = $buyerPaysSai ? (float) $term->base_amount : $payout;
            if ($principalAllocation > 0) $this->allocation($payment, 'advertiser_principal', (int)$term->advertiser_user_id, $principalAllocation);
            if ($buyerPaysSai && $brokerShare > 0) $this->allocation($payment, 'advertiser_sai_share', (int)$term->advertiser_user_id, $brokerShare);
        } elseif ($payment->mode === 'platform_sai_only') {
            if ($buyerPaysSai) {
                if ($platform > 0) $this->allocation($payment, 'platform_revenue', null, $platform);
                if ($brokerShare > 0) {
                    $payout = $brokerShare;
                    $this->allocation($payment, 'advertiser_sai_share', (int)$term->advertiser_user_id, $brokerShare);
                }
            } else {
                if ((float)$payment->required_amount > 0) $this->allocation($payment, 'platform_revenue', null, (float)$payment->required_amount);
            }
        } elseif ($payment->mode === 'platform_receivable') {
            $receivable = PropertyPlatformReceivable::query()->where('deal_financial_term_id',$term->id)->lockForUpdate()->firstOrFail();
            $remaining = max(0, (float)$receivable->amount_total - (float)$receivable->amount_paid);
            $applied = min($remaining, (float)$payment->required_amount);
            $receivable->amount_paid = round((float)$receivable->amount_paid + $applied, 2);
            $receivable->status = $receivable->amount_paid >= (float)$receivable->amount_total ? 'paid' : 'open';
            $receivable->paid_at = $receivable->status === 'paid' ? now() : null;
            $receivable->save();
            $this->allocation($payment, 'receivable_payment', null, $applied);
            if ($receivable->status === 'paid') {
                DB::table('property_financial_holds')->where('user_id',$term->advertiser_user_id)->whereNull('released_at')
                    ->update(['released_at'=>now(),'released_by_user_id'=>$reviewer->id,'release_reason'=>'platform_receivable_paid','updated_at'=>now()]);
                Property::query()->where('user_id',$term->advertiser_user_id)->update(['financial_hold_at'=>null,'financial_hold_reason'=>null]);
                $this->notifications->create((int)$term->advertiser_user_id,'financial_hold_released','تمت تسوية مستحقات المنصة','تم تأكيد السداد ورفع القيد المالي عن الإعلانات.','property_platform_receivable',$receivable->id,['receivable_id'=>$receivable->id]);
            }
        }

        $lines = [
            ['account_code'=>'payment_clearing','user_id'=>$payment->payer_user_id,'direction'=>'debit','amount'=>(float)$payment->required_amount,'currency'=>$payment->currency],
        ];
        if ($payment->mode === 'platform_receivable') {
            $lines[] = ['account_code'=>'advertiser_receivable','user_id'=>$term->advertiser_user_id,'direction'=>'credit','amount'=>(float)$payment->required_amount,'currency'=>$payment->currency];
        } else {
            $platformCredit = round((float)$payment->required_amount - $payout, 2);
            if ($platformCredit > 0) $lines[]=['account_code'=>'platform_revenue','user_id'=>null,'direction'=>'credit','amount'=>$platformCredit,'currency'=>$payment->currency];
            if ($payout > 0) $lines[]=['account_code'=>'advertiser_payable','user_id'=>$term->advertiser_user_id,'direction'=>'credit','amount'=>$payout,'currency'=>$payment->currency];
        }
        $this->postLedger('payment_confirmed','property_payment',$payment->id,$reviewer->id,'تأكيد دفعة عقارية',$lines);

        if ($payout > 0) {
            DB::table('property_payouts')->insert([
                'reference'=>$this->reference('OUT'),'deal_financial_term_id'=>$term->id,'property_payment_id'=>$payment->id,
                'advertiser_user_id'=>$term->advertiser_user_id,'amount'=>$payout,'currency'=>$payment->currency,
                'status'=>'pending','created_at'=>now(),'updated_at'=>now(),
            ]);
            $this->notifications->create((int)$term->advertiser_user_id,'property_payout_pending','مبلغ مستحق لك','تم تأكيد الدفع وأصبح المبلغ المستحق لك بانتظار التحويل.','property_payment',$payment->id,['payment_id'=>$payment->id,'amount'=>$payout,'currency'=>$payment->currency]);
        }
    }

    private function allocation(PropertyPayment $payment, string $type, ?int $beneficiaryUserId, float $amount): void
    {
        DB::table('property_payment_allocations')->insert([
            'property_payment_id'=>$payment->id,'allocation_type'=>$type,'beneficiary_user_id'=>$beneficiaryUserId,
            'amount'=>round($amount,2),'currency'=>$payment->currency,'created_at'=>now(),
        ]);
    }

    public function postLedger(string $entryType, string $sourceType, int $sourceId, ?int $actorId, string $memo, array $lines): int
    {
        $byCurrency = [];
        foreach ($lines as $line) {
            $currency = strtoupper((string)$line['currency']);
            $amount = round((float)$line['amount'],2);
            if ($amount <= 0) throw new ConflictHttpException('قيد مالي غير صالح.');
            $byCurrency[$currency][$line['direction']] = ($byCurrency[$currency][$line['direction']] ?? 0) + $amount;
        }
        foreach ($byCurrency as $currency => $totals) {
            if (abs(($totals['debit'] ?? 0) - ($totals['credit'] ?? 0)) > 0.005) {
                throw new ConflictHttpException('القيد المالي غير متوازن بعملة '.$currency.'.');
            }
        }
        $entryId = DB::table('property_financial_ledger_entries')->insertGetId([
            'reference'=>(string)Str::uuid(),'entry_type'=>$entryType,'source_type'=>$sourceType,'source_id'=>$sourceId,
            'created_by_user_id'=>$actorId,'memo'=>$memo,'occurred_at'=>now(),'created_at'=>now(),
        ]);
        foreach ($lines as $line) {
            DB::table('property_financial_ledger_lines')->insert([
                'ledger_entry_id'=>$entryId,'account_code'=>$line['account_code'],'user_id'=>$line['user_id'] ?? null,
                'direction'=>$line['direction'],'amount'=>round((float)$line['amount'],2),'currency'=>strtoupper((string)$line['currency']),
                'metadata'=>isset($line['metadata']) ? json_encode($line['metadata'], JSON_UNESCAPED_UNICODE) : null,'created_at'=>now(),
            ]);
        }
        return $entryId;
    }

    private function reference(string $prefix): string
    {
        return $prefix.'-'.now()->format('ymd').'-'.strtoupper(Str::random(10));
    }
}
