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
            $basis = $amount ?? ($property->purpose === 'rent' ? (float) ($property->monthly_rent ?: $property->price) : (float) $property->price);
            abort_unless($basis > 0, 422);
            $state = $property->purpose === 'rent' ? 'rented' : 'sold';
            $this->availability->change($actor, [(int)$property->id], $state, $request);
            $outcome = BrokerDealOutcome::query()->create([
                'reference'=>'DEAL-'.strtoupper(Str::random(12)), 'property_id'=>$property->id,
                'message_thread_id'=>$thread->id, 'advertiser_user_id'=>$actor->id, 'customer_user_id'=>$customerId,
                'sai_term_id'=>$thread->sai_term_id, 'status'=>'pending_customer', 'transaction_type'=>$property->purpose,
                'basis_amount'=>round($basis,2), 'currency'=>$property->currency,
                'snapshot'=>['property_title'=>$property->title,'advertiser_name'=>$actor->name,
                    'customer_name'=>User::query()->findOrFail($customerId)->name,
                    'record_kind'=>'external_transaction_result','basis'=>$property->purpose === 'rent' ? 'monthly_rent' : 'sale_price'],
                'advertiser_confirmed_at'=>now(),
            ]);
            $this->notifications->create($customerId, 'broker_deal_confirmation', 'هل تمت صفقة هذا العقار؟',
                'المعلن سجل أن الصفقة تمت خارج التطبيق. أكد النتيجة أو أبلغنا إذا لم تتم.',
                'broker_deal_outcome', $outcome->id, ['deal_id'=>$outcome->id,'thread_id'=>$thread->id,'property_id'=>$property->id]);
            $this->audit->record($actor,'broker.deal_reported',$outcome,['thread_id'=>$thread->id],$request,$customerId);
            return $outcome;
        });
    }

    public function decide(User $actor, BrokerDealOutcome $outcome, bool $confirmed, Request $request): BrokerDealOutcome
    {
        return DB::transaction(function () use ($actor, $outcome, $confirmed, $request): BrokerDealOutcome {
            Property::query()->withoutGlobalScopes()->whereKey($outcome->property_id)->lockForUpdate()->firstOrFail();
            MessageThread::query()->whereKey($outcome->message_thread_id)->lockForUpdate()->firstOrFail();
            $locked = BrokerDealOutcome::query()->lockForUpdate()->findOrFail($outcome->id);
            abort_unless((int)$locked->customer_user_id === (int)$actor->id, 403);
            if ($locked->status === 'confirmed' && $confirmed) return $locked;
            if ($locked->status === 'disputed' && ! $confirmed) return $locked;
            if ($locked->status !== 'pending_customer') throw new ConflictHttpException('نتيجة الصفقة حسمت أو تنتظر مراجعة؛ حدّث الصفحة.');
            if ($confirmed) {
                $locked->forceFill(['status'=>'confirmed','customer_confirmed_at'=>now(),'confirmed_at'=>now()])->save();
                $this->freezeFinance($locked, $request);
                MessageThread::query()->whereKey($locked->message_thread_id)->update(['lead_stage'=>'completed','lead_updated_at'=>now()]);
                if ($locked->support_case_id) {
                    $case=SupportCase::query()->find($locked->support_case_id);
                    if ($case && !in_array($case->status,SupportCaseService::CLOSED_STATUSES,true)) $this->support->setStatus($actor,$case,'resolved',$request);
                }
            } else {
                $case=$locked->support_case_id ? SupportCase::query()->find($locked->support_case_id) : null;
                if ($case && !in_array($case->status,SupportCaseService::CLOSED_STATUSES,true)) {
                    $case=$this->support->requesterReply($actor,$case,'لم تتم الصفقة، ولا أؤكد نتيجتها بعد طلب التأكيد مجددًا.',$request);
                } else $case = $this->support->create($actor,'support_ticket','مراجعة نتيجة صفقة',
                    'العميل لم يؤكد إتمام صفقة العقار '.$locked->snapshot['property_title'].'. لا تحتسب الصفقة أو يفتح تقييم حتى يحسم التأكيد.',
                    'broker_deal_outcome',$locked->id,'deal_not_confirmed','normal',$request);
                $locked->forceFill(['status'=>'disputed','support_case_id'=>$case->id])->save();
            }
            $this->notifications->create((int)$locked->advertiser_user_id, 'broker_deal_result',
                $confirmed ? 'تم تأكيد الصفقة' : 'نتيجة الصفقة تحتاج مراجعة',
                $confirmed ? 'أكد العميل إتمام الصفقة. سجلت النتيجة وفتح التقييم وفق السياسة.' : 'لم يؤكد العميل إتمام الصفقة. لن تحتسب حتى تحسم المراجعة.',
                'broker_deal_outcome',$locked->id,['deal_id'=>$locked->id,'thread_id'=>$locked->message_thread_id]);
            $this->audit->record($actor,$confirmed ? 'broker.deal_confirmed' : 'broker.deal_disputed',$locked,[],$request,$locked->advertiser_user_id);
            return $locked->fresh();
        });
    }

    public function resolveSupport(User $actor, SupportTask $task, string $decision, string $note, Request $request, bool $actingAsAgent=false): BrokerDealOutcome
    {
        $this->tasks->assertTaskExecution($actor,$task,$actingAsAgent);
        abort_unless(in_array($task->source_type,['support_ticket','report'],true),422);
        $case=SupportCase::query()->findOrFail($task->source_id);
        abort_unless($case->target_type === 'broker_deal_outcome',422);
        $outcome=BrokerDealOutcome::query()->findOrFail($case->target_id);
        return DB::transaction(function () use ($actor,$task,$case,$outcome,$decision,$note,$request,$actingAsAgent): BrokerDealOutcome {
            $property=Property::query()->withoutGlobalScopes()->whereKey($outcome->property_id)->lockForUpdate()->firstOrFail();
            $thread=MessageThread::query()->whereKey($outcome->message_thread_id)->lockForUpdate()->firstOrFail();
            $locked=BrokerDealOutcome::query()->whereKey($outcome->id)->lockForUpdate()->firstOrFail();
            $claimed=SupportTask::query()->whereKey($task->id)->lockForUpdate()->firstOrFail();
            $this->tasks->assertTaskExecution($actor,$claimed,$actingAsAgent);
            abort_unless($claimed->isActive() && $locked->status === 'disputed' && (int)$locked->support_case_id === (int)$case->id,409);
            $locked->forceFill(['status'=>$decision === 'retry' ? 'pending_customer' : 'cancelled',
                'resolved_by_user_id'=>$actor->id,'resolution_note'=>trim($note),'customer_confirmed_at'=>null,'confirmed_at'=>null])->save();
            if ($decision === 'cancel') {
                // A rejected completion claim can be made available again only by normal advertiser confirmation.
                $property->forceFill(['availability_status'=>'paused','availability_due_at'=>null,'availability_notified_at'=>null])->saveQuietly();
                $thread->forceFill(['lead_stage'=>'contacted','lead_updated_at'=>now()])->save();
            }
            $this->support->internalNote($actor,$case,trim($note),$request);
            $this->support->setStatus($actor,$case->fresh(),$decision === 'retry' ? 'waiting_requester' : 'dismissed',$request);
            foreach ([(int)$locked->customer_user_id,(int)$locked->advertiser_user_id] as $recipient) {
                $this->notifications->create($recipient,$decision === 'retry' ? 'broker_deal_confirmation' : 'broker_deal_result',
                    $decision === 'retry' ? 'مراجعة نتيجة الصفقة' : 'ألغيت نتيجة الصفقة',
                    $decision === 'retry' ? 'راجع نتيجة الصفقة مجددًا. لا تحتسب إلا بتأكيد العميل.' : 'ألغيت النتيجة بعد المراجعة دون احتساب صفقة أو مستحق جديد.',
                    'broker_deal_outcome',$locked->id,['deal_id'=>$locked->id]);
            }
            $this->audit->record($actor,'broker.deal_reviewed',$locked,['decision'=>$decision,'task_id'=>$task->id],$request,$locked->customer_user_id);
            return $locked->fresh();
        });
    }

    private function freezeFinance(BrokerDealOutcome $outcome, Request $request): void
    {
        if (PropertyDealFinancialTerm::query()->where('broker_deal_outcome_id',$outcome->id)->exists()) return;
        $sai = $outcome->sai_term_id ? PropertySaiTerm::query()->findOrFail($outcome->sai_term_id) : null;
        // Historical contacts without accepted Sai terms never gain a retroactive invented fee.
        if (! $sai) return;
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
                    'fixed_sai_currency'=>$sai->fixed_sai_currency]),'frozen_at'=>now(),
        ]);
        if ($amounts['platform_share'] <= 0) return;
        $due = PropertyPlatformReceivable::query()->create([
            'reference'=>'DUE-'.strtoupper(Str::random(12)),'deal_financial_term_id'=>$term->id,'property_id'=>$outcome->property_id,
            'advertiser_user_id'=>$outcome->advertiser_user_id,'amount_total'=>$amounts['platform_share'],'amount_paid'=>0,
            'currency'=>$outcome->currency,'status'=>'open','confirmed_direct_at'=>now(),'due_at'=>now()->addHours(24),
        ]);
        DB::table('property_financial_holds')->insert([
            'user_id'=>$outcome->advertiser_user_id,'reason'=>'platform_receivable_open','source_type'=>'property_platform_receivable',
            'source_id'=>$due->id,'started_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
        ]);
        $this->finance->postLedger('platform_receivable_created','property_platform_receivable',$due->id,null,'مستحق المنصة من صفقة مؤكدة خارج التطبيق',[
            ['account_code'=>'advertiser_receivable','user_id'=>$outcome->advertiser_user_id,'direction'=>'debit','amount'=>$amounts['platform_share'],'currency'=>$outcome->currency],
            ['account_code'=>'platform_revenue','user_id'=>null,'direction'=>'credit','amount'=>$amounts['platform_share'],'currency'=>$outcome->currency],
        ]);
        $this->notifications->create((int)$outcome->advertiser_user_id,'platform_receivable_created','مستحق للمنصة',
            'المستحق محسوب من نسخة شروط السعي المحفوظة لهذه المحادثة. سدده خلال 24 ساعة وفق السياسة الحالية.',
            'property_platform_receivable',$due->id,['receivable_id'=>$due->id,'due_at'=>$due->due_at->toIso8601String()]);
    }
}
