<?php

namespace App\Services;

use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPlatformReceivable;
use App\Models\PropertySaiTerm;
use App\Models\SupportCase;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class BrokerDealService
{
    public const PRICE_CONFIRMATION_REASON = 'deal_price_confirmation';

    public function __construct(
        private readonly BrokerAvailabilityService $availability,
        private readonly PropertySaiService $sai,
        private readonly PropertyFinancialService $finance,
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
        private readonly SupportCaseService $support,
        private readonly SupportTaskService $tasks,
    ) {}

    public function report(User $actor, MessageThread $thread, ?float $amount, Request $request): BrokerDealOutcome
    {
        abort_unless($actor->hasApprovedVerificationProfile(), 403);
        return DB::transaction(function () use ($actor, $thread, $amount, $request): BrokerDealOutcome {
            $property = Property::query()->withoutGlobalScopes()->lockForUpdate()->findOrFail($thread->property_id);
            $thread = MessageThread::query()->lockForUpdate()->findOrFail($thread->id);
            abort_unless((int) $property->user_id === (int) $actor->id, 403);
            $customerId = (int) $thread->started_by_user_id;
            abort_unless($customerId !== (int) $actor->id && $customerId > 0
                && $thread->participants()->where('user_id',$actor->id)->exists()
                && $thread->participants()->where('user_id',$customerId)->exists(), 409);
            $existing = BrokerDealOutcome::query()->where('message_thread_id',$thread->id)->first();
            if ($existing) return $existing;
            abort_if(BrokerDealOutcome::query()->where('property_id', $property->id)
                ->whereIn('status', ['pending_customer', 'disputed'])->exists(),
                409, 'هناك طلب صفقة لهذا الإعلان قيد المراجعة.');
            $frozenTerm = $thread->sai_term_id ? PropertySaiTerm::query()->find($thread->sai_term_id) : null;
            if ($frozenTerm?->sai_amount_type === 'fixed' && $frozenTerm->fixed_sai_currency !== $property->currency) {
                throw new ConflictHttpException('عملة الصفقة لا تطابق عملة مبلغ السعي المحفوظ لهذه المحادثة.');
            }
            if ($frozenTerm && $frozenTerm->platform_terms_status === 'pending' && ! $this->sai->hasPlatformConsent($frozenTerm)) {
                throw new \Illuminate\Http\Exceptions\HttpResponseException(response()->json([
                    'message'=>'راجع إقرار السعي المحفوظ لهذه المحادثة قبل تسجيل إتمام الصفقة.', 'code'=>'sai_consent_required',
                    'data'=>['property_id'=>(int)$property->id,'sai_term_id'=>(int)$frozenTerm->id,
                        'text'=>$this->finance->attestationText($property,$frozenTerm)],
                ],409));
            }
            $listingPrice = round($property->purpose === 'rent'
                ? (float) ($property->monthly_rent ?: $property->price)
                : (float) $property->price, 2);
            $basis = round($amount ?? $listingPrice, 2);
            abort_unless($listingPrice > 0, 422, 'أضف سعر الإعلان قبل تسجيل نتيجة الصفقة.');
            abort_unless($basis > 0, 422, 'أدخل مبلغ صفقة صحيحًا.');
            $requiresConfirmation = $basis < $listingPrice;
            if ($requiresConfirmation) {
                abort_unless($property->isPubliclyVisible() && $property->review_status === 'approved',
                    409, 'تأكيد سعر أقل متاح للإعلانات المنشورة والمعتمدة.');
            }
            $customer = User::query()->findOrFail($customerId);
            $outcome = BrokerDealOutcome::query()->create([
                'reference'=>'DEAL-'.strtoupper(Str::random(12)), 'property_id'=>$property->id,
                'message_thread_id'=>$thread->id, 'advertiser_user_id'=>$actor->id, 'customer_user_id'=>$customerId,
                'sai_term_id'=>$thread->sai_term_id, 'status'=>'pending_customer', 'transaction_type'=>$property->purpose,
                'basis_amount'=>$basis, 'currency'=>$property->currency,
                'snapshot'=>['property_title'=>$property->title,'advertiser_name'=>$actor->name,
                    'customer_name'=>$customer->name,
                    'listing_price'=>$listingPrice > 0 ? $listingPrice : null,
                    'listing_currency'=>$listingPrice > 0 ? $property->currency : null,
                    'record_kind'=>'app_customer_transaction_result','basis'=>$property->purpose === 'rent' ? 'monthly_rent' : 'sale_price',
                    'price_confirmation_required'=>$requiresConfirmation],
                'advertiser_confirmed_at'=>now(),
                'advertiser_attention_revision'=>1,
            ]);
            if ($requiresConfirmation) {
                $case = $this->support->create($customer, 'support_ticket', 'تأكيد سعر الصفقة',
                    'أبلغ المعلن عن صفقة بسعر أقل من سعر الإعلان. يرجى تأكيد مبلغ الصفقة أو إبلاغ الدعم إن لم تتم.',
                    'broker_deal_outcome', $outcome->id, self::PRICE_CONFIRMATION_REASON, 'normal', $request,
                    initiator: $actor);
                $outcome->forceFill(['support_case_id' => $case->id])->save();
            } else {
                $this->closeListing($actor, $property, $outcome, $request);
                $this->confirmOutcome($outcome, $request);
            }
            $this->notifications->create(
                $customerId,
                $requiresConfirmation ? 'broker_deal_confirmation' : 'broker_deal_result',
                $requiresConfirmation ? 'أكّد سعر صفقة العقار' : 'تم تسجيل صفقة العقار',
                $requiresConfirmation ? 'أبلغ المعلن عن سعر أقل من سعر الإعلان. راجع المبلغ وأكّد الصفقة أو ارفضها.'
                    : 'سُجلت صفقة العقار المرتبطة بمحادثتك ويمكنك مراجعة تفاصيلها.',
                'broker_deal_outcome', $outcome->id, $this->notificationData($outcome),
            );
            $this->audit->record($actor,'broker.deal_reported',$outcome,
                ['thread_id'=>$thread->id,'status'=>$outcome->status],$request,$customerId);
            return $outcome;
        }, 3);
    }

    public function decide(User $actor, BrokerDealOutcome $outcome, bool $confirmed, Request $request): BrokerDealOutcome
    {
        return DB::transaction(function () use ($actor, $outcome, $confirmed, $request): BrokerDealOutcome {
            $property = Property::query()->withoutGlobalScopes()->whereKey($outcome->property_id)->lockForUpdate()->firstOrFail();
            MessageThread::query()->whereKey($outcome->message_thread_id)->lockForUpdate()->firstOrFail();
            $locked = BrokerDealOutcome::query()->lockForUpdate()->findOrFail($outcome->id);
            abort_unless((int)$locked->customer_user_id === (int)$actor->id, 403);
            if ($locked->status === 'confirmed' && $confirmed) return $locked;
            if ($locked->status === 'disputed' && ! $confirmed) return $locked;
            if ($locked->status !== 'pending_customer') throw new ConflictHttpException('نتيجة الصفقة حسمت أو تنتظر مراجعة؛ حدّث الصفحة.');
            $locked->advertiser_attention_revision = (int) $locked->advertiser_attention_revision + 1;
            $priceReview = $locked->requiresPriceConfirmation();
            $hasDue = false;
            if ($confirmed) {
                if ($priceReview) {
                    $this->closeListing($locked->advertiser()->firstOrFail(), $property, $locked, $request);
                }
                $locked->customer_confirmed_at = now();
                $hasDue = $this->confirmOutcome($locked, $request);
                if ($locked->support_case_id) {
                    $case=SupportCase::query()->lockForUpdate()->find($locked->support_case_id);
                    if ($case && !in_array($case->status,SupportCaseService::CLOSED_STATUSES,true)) $this->support->setStatus($actor,$case,'resolved',$request);
                }
            } else {
                $case=$locked->support_case_id ? SupportCase::query()->lockForUpdate()->find($locked->support_case_id) : null;
                if ($case && !in_array($case->status,SupportCaseService::CLOSED_STATUSES,true)) {
                    $message = $priceReview
                        ? 'لم أؤكد مبلغ الصفقة أو إتمامها.'
                        : 'لم تتم الصفقة، ولا أؤكد نتيجتها بعد طلب التأكيد مجددًا.';
                    $case=$this->support->requesterReply($actor,$case,$message,$request);
                } else $case = $this->support->create($actor,'support_ticket','مراجعة نتيجة صفقة',
                    'العميل لم يؤكد إتمام صفقة العقار '.$locked->snapshot['property_title'].'. لا تحتسب الصفقة أو يفتح تقييم حتى يحسم التأكيد.',
                    'broker_deal_outcome',$locked->id,$priceReview ? self::PRICE_CONFIRMATION_REASON
                        : 'deal_not_confirmed','normal',$request);
                $locked->forceFill(['status'=>'disputed','support_case_id'=>$case->id])->save();
            }
            [$title, $body] = match (true) {
                $confirmed && $priceReview => ['تم تأكيد مبلغ الصفقة', 'أكد العميل مبلغ الصفقة.'],
                $confirmed => ['تم تأكيد الصفقة', 'أكد العميل إتمام الصفقة. سجلت النتيجة وفتح التقييم وفق السياسة.'],
                default => ['نتيجة الصفقة تحتاج مراجعة', 'لم يؤكد العميل إتمام الصفقة. لن تحتسب حتى تحسم المراجعة.'],
            };
            if ($hasDue && $priceReview) $body .= ' يرجى سداد مستحق المنصة.';
            $this->notifications->create((int)$locked->advertiser_user_id, 'broker_deal_result', $title, $body,
                'broker_deal_outcome',$locked->id,$this->notificationData($locked));
            $this->audit->record($actor,$confirmed ? 'broker.deal_confirmed' : 'broker.deal_disputed',$locked,[],$request,$locked->advertiser_user_id);
            return $locked->fresh();
        }, 3);
    }

    public function resolveSupport(User $actor, SupportTask $task, string $decision, string $note, Request $request, bool $actingAsAgent=false): BrokerDealOutcome
    {
        $this->tasks->assertTaskExecution($actor,$task,$actingAsAgent);
        abort_unless(in_array($task->source_type,['support_ticket','report'],true),422);
        $case=SupportCase::query()->findOrFail($task->source_id);
        abort_unless($case->target_type === 'broker_deal_outcome',422);
        $outcome=BrokerDealOutcome::query()->findOrFail($case->target_id);
        abort_if(in_array((int) $actor->id, [(int) $outcome->advertiser_user_id, (int) $outcome->customer_user_id], true), 403);
        return DB::transaction(function () use ($actor,$task,$case,$outcome,$decision,$note,$request,$actingAsAgent): BrokerDealOutcome {
            $property=Property::query()->withoutGlobalScopes()->whereKey($outcome->property_id)->lockForUpdate()->firstOrFail();
            $thread=MessageThread::query()->whereKey($outcome->message_thread_id)->lockForUpdate()->firstOrFail();
            $locked=BrokerDealOutcome::query()->whereKey($outcome->id)->lockForUpdate()->firstOrFail();
            $case=SupportCase::query()->whereKey($case->id)->lockForUpdate()->firstOrFail();
            $claimed=SupportTask::query()->whereKey($task->id)->lockForUpdate()->firstOrFail();
            $this->tasks->assertTaskExecution($actor,$claimed,$actingAsAgent);
            $priceReview = $locked->requiresPriceConfirmation() && $case->reason_code === self::PRICE_CONFIRMATION_REASON;
            $acceptableStatuses = match ($decision) {
                'approve' => $priceReview ? ['pending_customer'] : [],
                'cancel' => $priceReview ? ['pending_customer', 'disputed'] : ['disputed'],
                default => ['disputed'],
            };
            abort_if($decision === 'approve' && !$priceReview, 422);
            abort_unless(
                $claimed->isActive() && (int) $claimed->source_id === (int) $case->id
                    && in_array($case->status, SupportCaseService::ACTIVE_STATUSES, true)
                    && in_array($locked->status, $acceptableStatuses, true)
                    && (int)$locked->support_case_id === (int)$case->id,
                409,
            );
            $locked->forceFill(['resolved_by_user_id'=>$actor->id,'resolution_note'=>trim($note),
                'customer_confirmed_at'=>null,'confirmed_at'=>null,
                'advertiser_attention_revision'=>(int) $locked->advertiser_attention_revision + 1]);
            $hasDue = false;
            if ($decision === 'approve') {
                $this->closeListing($locked->advertiser()->firstOrFail(), $property, $locked, $request);
                $hasDue = $this->confirmOutcome($locked, $request);
            } else {
                $locked->forceFill(['status'=>$decision === 'retry' ? 'pending_customer' : 'cancelled'])->save();
            }
            if ($decision === 'cancel' && !$locked->requiresPriceConfirmation()) {
                // A rejected completion claim can be made available again only by normal advertiser confirmation.
                $property->forceFill(['availability_status'=>'paused','availability_due_at'=>null,'availability_notified_at'=>null])->saveQuietly();
                PropertyDiscoveryFilterService::refreshNearbyVisibilityAfterCommit();
                $thread->forceFill(['lead_stage'=>'contacted','lead_updated_at'=>now()])->save();
            }
            $this->support->internalNote($actor,$case,trim($note),$request);
            [$caseStatus, $notificationType, $title, $body] = match ($decision) {
                'approve' => ['resolved', 'broker_deal_result', 'تم تأكيد مبلغ الصفقة', 'أكد الدعم مبلغ الصفقة وسجل نتيجتها.'],
                'retry' => ['waiting_requester', 'broker_deal_confirmation', 'مراجعة نتيجة الصفقة', 'راجع نتيجة الصفقة مجددًا. لا تحتسب إلا بعد تأكيدها.'],
                default => ['dismissed', 'broker_deal_result', 'ألغيت نتيجة الصفقة', 'ألغيت النتيجة بعد المراجعة دون احتساب صفقة أو مستحق جديد.'],
            };
            $this->support->setStatus($actor,$case->fresh(),$caseStatus,$request);
            foreach ([(int)$locked->customer_user_id,(int)$locked->advertiser_user_id] as $recipient) {
                $message = $hasDue && $recipient === (int) $locked->advertiser_user_id
                    ? $body.' يرجى سداد مستحق المنصة.' : $body;
                $this->notifications->create($recipient,$notificationType,$title,$message,
                    'broker_deal_outcome',$locked->id,$this->notificationData($locked));
            }
            $this->audit->record($actor,'broker.deal_reviewed',$locked,['decision'=>$decision,'task_id'=>$task->id],$request,$locked->customer_user_id);
            return $locked->fresh();
        }, 3);
    }

    public function remindSupportOfPendingPrices(int $limit = 100): int
    {
        $ids = BrokerDealOutcome::query()->where('status', 'pending_customer')->whereNotNull('support_case_id')
            ->where('snapshot->price_confirmation_required', true)
            ->whereNull('snapshot->price_staff_reminded_at')
            ->where('advertiser_confirmed_at', '<=', now()->subHours(24))
            ->orderBy('id')->limit($limit)->pluck('id');
        $reminded = 0;
        foreach ($ids as $id) {
            $reminded += (int) DB::transaction(function () use ($id): bool {
                $outcome = BrokerDealOutcome::query()->lockForUpdate()->findOrFail($id);
                if ($outcome->status !== 'pending_customer' || !$outcome->requiresPriceConfirmation()
                    || isset($outcome->snapshot['price_staff_reminded_at'])) return false;

                $case = SupportCase::query()->lockForUpdate()->findOrFail($outcome->support_case_id);
                $task = SupportTask::query()->where('source_type', 'support_ticket')
                    ->where('source_id', $case->id)->lockForUpdate()->first();
                if (!$task?->isActive() || !in_array($case->status, SupportCaseService::ACTIVE_STATUSES, true)
                    || !$this->tasks->notifyDealPriceConfirmationDue($task, $outcome->id)) return false;

                $outcome->forceFill(['snapshot' => $outcome->snapshot + ['price_staff_reminded_at' => now()->toIso8601String()]])->save();
                return true;
            }, 3);
        }
        return $reminded;
    }

    private function closeListing(User $advertiser, Property $property, BrokerDealOutcome $outcome, Request $request): void
    {
        abort_unless($property->purpose === $outcome->transaction_type && $property->currency === $outcome->currency,
            409, 'تغيّر نوع الإعلان أو عملته منذ تسجيل الصفقة.');
        $state = $property->purpose === 'rent' ? 'rented' : 'sold';
        $this->availability->change($advertiser, [(int) $property->id], $state, $request, auditActor: $request->user());
    }

    private function confirmOutcome(BrokerDealOutcome $outcome, Request $request): bool
    {
        $outcome->forceFill(['status' => 'confirmed', 'confirmed_at' => now()])->save();
        $hasDue = $this->freezeFinance($outcome, $request);
        $outcome->thread()->update(['lead_stage' => 'completed', 'lead_updated_at' => now()]);
        return $hasDue;
    }

    private function notificationData(BrokerDealOutcome $outcome): array
    {
        return ['deal_id' => $outcome->id, 'thread_id' => $outcome->message_thread_id,
            'property_id' => $outcome->property_id];
    }

    private function freezeFinance(BrokerDealOutcome $outcome, Request $request): bool
    {
        if (PropertyDealFinancialTerm::query()->where('broker_deal_outcome_id',$outcome->id)->exists()) return false;
        $sai = $outcome->sai_term_id ? PropertySaiTerm::query()->findOrFail($outcome->sai_term_id) : null;
        // Historical contacts without accepted Sai terms never gain a retroactive invented fee.
        if (! $sai) return false;
        if ((int)$sai->property_id !== (int)$outcome->property_id || $sai->purpose !== $outcome->transaction_type) {
            throw new ConflictHttpException('نسخة شروط السعي المحفوظة لا تطابق العقار.');
        }
        $this->sai->assertSettlementConsent($sai);
        $amounts = $this->sai->calculateSaiAmount($sai, (float)$outcome->basis_amount);
        $term = PropertyDealFinancialTerm::query()->create([
            'broker_deal_outcome_id'=>$outcome->id,'property_agreement_id'=>null,'property_agreement_revision_id'=>null,
            'property_id'=>$outcome->property_id,'buyer_user_id'=>$outcome->customer_user_id,'advertiser_user_id'=>$outcome->advertiser_user_id,
            'transaction_type'=>$outcome->transaction_type,'advertiser_type'=>$sai->advertiser_type,'currency'=>$outcome->currency,
            'base_amount'=>$outcome->basis_amount,'monthly_basis_amount'=>$outcome->transaction_type === 'rent' ? $outcome->basis_amount : null,
            'sai_payer'=>$sai->payer,'sai_total_amount'=>$amounts['total_sai'],'platform_share_amount'=>$amounts['platform_share'],
            'advertiser_sai_share_amount'=>$amounts['broker_share'],'snapshot'=>array_merge($outcome->snapshot,
                ['deal_reference'=>$outcome->reference,'sai_term_id'=>$sai->id,'sai_version'=>$sai->version,
                    'sai_amount_type'=>$sai->sai_amount_type,'fixed_sai_amount'=>$sai->fixed_sai_amount,
                    'sai_rate_percent'=>$sai->sai_amount_type === 'fixed' ? null : $sai->sai_rate_percent,
                    'fixed_sai_currency'=>$sai->fixed_sai_currency]),'frozen_at'=>now(),
        ]);
        if ($amounts['platform_share'] <= 0) return false;
        $due = PropertyPlatformReceivable::query()->create([
            'reference'=>'DUE-'.strtoupper(Str::random(12)),'deal_financial_term_id'=>$term->id,'property_id'=>$outcome->property_id,
            'advertiser_user_id'=>$outcome->advertiser_user_id,'amount_total'=>$amounts['platform_share'],'amount_paid'=>0,
            'currency'=>$outcome->currency,'status'=>'open','confirmed_direct_at'=>now(),'due_at'=>now()->addHours(24),
        ]);
        DB::table('property_financial_holds')->insert([
            'user_id'=>$outcome->advertiser_user_id,'reason'=>'platform_receivable_open','source_type'=>'property_platform_receivable',
            'source_id'=>$due->id,'started_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
        ]);
        $this->finance->postLedger('platform_receivable_created','property_platform_receivable',$due->id,null,'مستحق المنصة من صفقة مؤكدة',[
            ['account_code'=>'advertiser_receivable','user_id'=>$outcome->advertiser_user_id,'direction'=>'debit','amount'=>$amounts['platform_share'],'currency'=>$outcome->currency],
            ['account_code'=>'platform_revenue','user_id'=>null,'direction'=>'credit','amount'=>$amounts['platform_share'],'currency'=>$outcome->currency],
        ]);
        $this->notifications->create((int)$outcome->advertiser_user_id,'platform_receivable_created','مستحق للمنصة',
            'المستحق محسوب من نسخة شروط السعي المحفوظة لهذه المحادثة. سدده خلال 24 ساعة وفق السياسة الحالية.',
            'property_platform_receivable',$due->id,['receivable_id'=>$due->id,'due_at'=>$due->due_at->toIso8601String()]);
        return true;
    }
}
