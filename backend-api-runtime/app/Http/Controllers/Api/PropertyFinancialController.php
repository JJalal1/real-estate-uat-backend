<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyAgreement;
use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPayment;
use App\Models\PropertyPaymentMethod;
use App\Models\PropertyPlatformReceivable;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\PropertyFinancialService;
use App\Services\SupportTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertyFinancialController extends Controller
{
    public function __construct(
        private readonly PropertyFinancialService $finance,
        private readonly CloudAssetStorageService $storage,
        private readonly SupportTaskService $supportTasks,
        private readonly AuditLogService $audit,
    ) {}

    public function deal(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $this->assertAgreementParty($user,$agreement);
        $term=$this->finance->ensureFinancialTerm($agreement);
        return response()->json(['data'=>$this->dealData($term,$user,true)]);
    }

    public function createPayment(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$this->assertAgreementParty($user,$agreement);
        $validated=$request->validate([
            'mode'=>['required',Rule::in(['platform_full','platform_sai_only'])],
            'payment_method_id'=>['required','integer','exists:property_payment_methods,id'],
        ]);
        $term=$this->finance->ensureFinancialTerm($agreement);
        $method=PropertyPaymentMethod::query()->findOrFail((int)$validated['payment_method_id']);
        $payment=$this->finance->createPayment($term,$user,$validated['mode'],$method,$request);
        return response()->json(['message'=>'تم إنشاء عملية الدفع.','data'=>$this->paymentData($payment,$user)],201);
    }

    public function createReceivablePayment(Request $request, PropertyPlatformReceivable $receivable): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$receivable->advertiser_user_id===(int)$user->id,403);
        $validated=$request->validate(['payment_method_id'=>['required','integer','exists:property_payment_methods,id']]);
        $term=PropertyDealFinancialTerm::query()->findOrFail($receivable->deal_financial_term_id);
        $method=PropertyPaymentMethod::query()->findOrFail((int)$validated['payment_method_id']);
        $payment=$this->finance->createPayment($term,$user,'platform_receivable',$method,$request);
        return response()->json(['message'=>'تم إنشاء عملية تسديد المستحق.','data'=>$this->paymentData($payment,$user)],201);
    }

    public function submitProof(Request $request, PropertyPayment $payment): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$payment->payer_user_id===(int)$user->id,403);
        $method=PropertyPaymentMethod::query()->findOrFail($payment->payment_method_id);
        $rules=[
            'proof'=>['required','file','image','mimes:jpg,jpeg,png,webp','max:10240'],
            'provider_reference'=>['nullable','string','max:120'],
            'sender_name'=>['nullable','string','max:160'],
            'sender_phone'=>[$method->requires_sender_phone?'required':'nullable','string','max:40'],
        ];
        $validated=$request->validate($rules);$file=$request->file('proof');
        $path=$this->storage->storePrivate($file,'financial/payment-proofs/'.$payment->id);
        try {
            $updated=$this->finance->submitProof($payment,$user,[
                'provider_reference'=>$validated['provider_reference']??null,'sender_name'=>$validated['sender_name']??null,
                'sender_phone'=>$validated['sender_phone']??null,'proof_path'=>$path,'proof_original_name'=>$file->getClientOriginalName(),
                'proof_mime_type'=>$file->getMimeType(),'proof_size_bytes'=>$file->getSize(),
            ],$request);
        } catch (\Throwable $e) {
            $this->storage->deletePrivate($path);throw $e;
        }
        $this->supportTasks->projectPayment($updated);
        return response()->json(['message'=>'تم استلام إثبات الدفع وهو الآن بانتظار التحقق.','data'=>$this->paymentData($updated,$user)]);
    }

    public function proof(Request $request, PropertyPayment $payment): Response
    {
        /** @var User $user */ $user=$request->user();
        $allowed=(int)$payment->payer_user_id===(int)$user->id || $user->is_platform_owner || $user->hasRole('super_admin') || $user->hasPermission('payments.review') || $user->hasPermission('finance.manage');
        abort_unless($allowed,403);abort_unless($payment->proof_path,404);
        return $this->storage->responsePrivate($payment->proof_path,$payment->proof_original_name ?: 'payment-proof');
    }

    public function paymentsMine(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=PropertyPayment::query()->with('method')->where('payer_user_id',$user->id)->latest('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(PropertyPayment $p)=>$this->paymentData($p,$user))->values()]);
    }

    public function financialAccount(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless($user->hasApprovedVerificationProfile(),403);
        $receivables=PropertyPlatformReceivable::query()->where('advertiser_user_id',$user->id)->latest('id')->limit(250)->get();
        $payouts=DB::table('property_payouts')->where('advertiser_user_id',$user->id)->latest('id')->limit(250)->get();
        $deals=PropertyDealFinancialTerm::query()->where('advertiser_user_id',$user->id)->latest('id')->limit(250)->get();
        return response()->json(['data'=>[
            'summary'=>$this->finance->financialSummaryFor($user),
            'receivables'=>$receivables->map(fn($r)=>$this->receivableData($r))->values(),
            'payouts'=>$payouts->map(fn($p)=>['id'=>$p->id,'reference'=>$p->reference,'amount'=>(float)$p->amount,'currency'=>$p->currency,'status'=>$p->status,'paid_at'=>$p->paid_at])->values(),
            'deals'=>$deals->map(fn(PropertyDealFinancialTerm $t)=>$this->dealData($t,$user,false))->values(),
        ]]);
    }

    public function confirmDirect(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$this->assertAgreementParty($user,$agreement);
        $validated=$request->validate(['decision'=>['required',Rule::in(['confirmed','disputed'])],'note'=>['nullable','string','max:2000']]);
        $term=$this->finance->ensureFinancialTerm($agreement);
        $result=$this->finance->confirmDirectPayment($term,$user,$validated['decision'],$validated['note']??null,$request);
        return response()->json(['message'=>$result['disputed']?'تم تسجيل الاعتراض للمراجعة.':($result['completed']?'تم تأكيد الصفقة المباشرة من الطرفين.':'تم تسجيل تأكيدك وبانتظار الطرف الآخر.'),'data'=>[
            'completed'=>$result['completed'],'disputed'=>$result['disputed'],'receivable'=>$result['receivable']?$this->receivableData($result['receivable']):null,
        ]]);
    }

    public function attestSai(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$this->finance->attestSai($property,$user,$request);
        return response()->json(['message'=>'تم تسجيل إقرار السعي.']);
    }

    public function review(Request $request, PropertyPayment $payment): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['decision'=>['required',Rule::in(['confirm','correction','reject'])],'note'=>['nullable','string','max:2000'],'acting_as_agent'=>['nullable','boolean']]);
        abort_unless($actor->hasPermission('payments.review'),403);
        if ($actor->hasRole('support_manager') && !$actor->is_platform_owner && !$actor->hasRole('super_admin') && !$request->boolean('acting_as_agent')) {
            throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل مراجعة إثبات الدفع بنفسك.');
        }
        $task=SupportTask::query()->where('source_type','payment_review')->where('source_id',$payment->id)->firstOrFail();
        abort_unless((int)$task->assigned_to_user_id===(int)$actor->id || $actor->is_platform_owner || $actor->hasRole('super_admin'),403,'يجب استلام مهمة التحقق أو إسنادها لك أولاً.');
        $updated=$this->finance->reviewPayment($payment,$actor,$validated['decision'],$validated['note']??null,$request);
        $this->supportTasks->projectPayment($updated);
        return response()->json(['message'=>'تم تحديث مراجعة الدفع.','data'=>$this->paymentData($updated,$actor)]);
    }

    public function adminSummary(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();abort_unless($actor->hasPermission('finance.view')||$actor->hasPermission('finance.manage'),403);
        $open=PropertyPlatformReceivable::query()->whereIn('status',['open','under_review','overdue','disputed'])->whereColumn('amount_paid','<','amount_total');
        $data=[
            'payments_waiting_review'=>PropertyPayment::query()->whereIn('status',['proof_submitted','under_review'])->count(),
            'confirmed_payments_amount'=>(float)PropertyPayment::query()->where('status','confirmed')->sum('required_amount'),
            'open_receivables_amount'=>(float)(clone $open)->selectRaw('COALESCE(SUM(amount_total-amount_paid),0) total')->value('total'),
            'overdue_receivables_amount'=>(float)(clone $open)->where('due_at','<=',now())->selectRaw('COALESCE(SUM(amount_total-amount_paid),0) total')->value('total'),
            'overdue_accounts'=>(clone $open)->where('due_at','<=',now())->distinct('advertiser_user_id')->count('advertiser_user_id'),
            'pending_payouts_amount'=>(float)DB::table('property_payouts')->where('status','pending')->sum('amount'),
            'open_disputes'=>DB::table('property_financial_disputes')->where('status','open')->count(),
        ];
        return response()->json(['data'=>$data]);
    }

    public function adminPaymentMethods(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();abort_unless($actor->hasPermission('finance.manage'),403);
        return response()->json(['data'=>PropertyPaymentMethod::query()->orderBy('sort_order')->get()]);
    }

    public function updatePaymentMethod(Request $request, PropertyPaymentMethod $method): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();abort_unless($actor->hasPermission('finance.manage'),403);
        $validated=$request->validate([
            'name_ar'=>['sometimes','string','max:80'],'beneficiary_name'=>['sometimes','string','max:160'],
            'destination_label'=>['sometimes','string','max:80'],'destination_value'=>['sometimes','string','max:120'],
            'currency'=>['sometimes','string','size:3'],'min_amount'=>['nullable','numeric','min:0'],'max_amount'=>['nullable','numeric','min:0'],
            'instructions_ar'=>['nullable','string','max:2000'],'is_enabled'=>['sometimes','boolean'],'sort_order'=>['sometimes','integer','min:0','max:1000'],
        ]);
        if(isset($validated['currency']))$validated['currency']=strtoupper($validated['currency']);
        $method->fill($validated)->save();
        $this->audit->record($actor,'finance.payment_method_updated',$method,['changed_fields'=>array_keys($validated)],$request);
        return response()->json(['message'=>'تم تحديث طريقة الدفع.','data'=>$method->fresh()]);
    }

    public function recordPayout(Request $request, int $payout): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();abort_unless($actor->hasPermission('finance.manage'),403);
        $validated=$request->validate(['external_reference'=>['nullable','string','max:120'],'note'=>['nullable','string','max:2000']]);
        $row=DB::table('property_payouts')->where('id',$payout)->lockForUpdate()->first();abort_unless($row,404);
        if($row->status!=='pending')throw new ConflictHttpException('التحويل ليس بانتظار التنفيذ.');
        DB::transaction(function()use($row,$actor,$validated):void{
            DB::table('property_payouts')->where('id',$row->id)->update(['status'=>'paid','external_reference'=>$validated['external_reference']??null,'note'=>$validated['note']??null,'recorded_by_user_id'=>$actor->id,'paid_at'=>now(),'updated_at'=>now()]);
            $this->finance->postLedger('payout_paid','property_payout',$row->id,$actor->id,'تحويل مستحق صاحب الإعلان',[
                ['account_code'=>'advertiser_payable','user_id'=>$row->advertiser_user_id,'direction'=>'debit','amount'=>(float)$row->amount,'currency'=>$row->currency],
                ['account_code'=>'payment_clearing','user_id'=>null,'direction'=>'credit','amount'=>(float)$row->amount,'currency'=>$row->currency],
            ]);
        });
        return response()->json(['message'=>'تم تسجيل التحويل للمستفيد.']);
    }

    private function assertAgreementParty(User $user, PropertyAgreement $agreement): void
    {
        abort_unless(in_array((int)$user->id,[(int)$agreement->requester_user_id,(int)$agreement->advertiser_user_id],true),403);
        abort_unless($agreement->status==='accepted',409,'يجب اعتماد الاتفاق من الطرفين قبل بدء التسوية المالية.');
    }

    private function dealData(PropertyDealFinancialTerm $term, User $viewer, bool $includeMethods): array
    {
        $buyerPays=in_array($term->sai_payer,['buyer','tenant'],true);
        $fullRequired=round((float)$term->base_amount+($buyerPays?(float)$term->sai_total_amount:0),2);
        $data=[
            'id'=>$term->id,'agreement_id'=>$term->property_agreement_id,'property_id'=>$term->property_id,'transaction_type'=>$term->transaction_type,
            'advertiser_type'=>$term->advertiser_type,'currency'=>$term->currency,'base_amount'=>(float)$term->base_amount,
            'monthly_rent'=>$term->monthly_basis_amount!==null?(float)$term->monthly_basis_amount:null,'rental_term_months'=>$term->rental_term_months,
            'advance_months'=>$term->advance_months,'sai_payer'=>$term->sai_payer,'sai_total_amount'=>(float)$term->sai_total_amount,
            'required_full_payment'=>$fullRequired,'price_display_mode'=>$term->price_display_mode,'is_buyer'=>(int)$viewer->id===(int)$term->buyer_user_id,
            'is_advertiser'=>(int)$viewer->id===(int)$term->advertiser_user_id,'frozen_at'=>$term->frozen_at?->toIso8601String(),
        ];
        if((int)$viewer->id===(int)$term->advertiser_user_id){
            $data['platform_share_amount']=(float)$term->platform_share_amount;$data['advertiser_sai_share_amount']=(float)$term->advertiser_sai_share_amount;
        }
        if($includeMethods){
            $amount=(int)$viewer->id===(int)$term->buyer_user_id?$fullRequired:($this->finance->hasOpenReceivable((int)$viewer->id)?(float)$term->platform_share_amount:0);
            $data['payment_methods']=$amount>0?$this->finance->paymentMethods($amount,$term->currency):[];
        }
        return $data;
    }

    private function paymentData(PropertyPayment $payment, User $viewer): array
    {
        $payment->loadMissing('method');
        return [
            'id'=>$payment->id,'reference'=>$payment->reference,'property_id'=>$payment->property_id,'mode'=>$payment->mode,'status'=>$payment->status,
            'required_amount'=>(float)$payment->required_amount,'currency'=>$payment->currency,'payment_method'=>$payment->method?[
                'id'=>$payment->method->id,'key'=>$payment->method->key,'name_ar'=>$payment->method->name_ar,'asset_key'=>$payment->method->asset_key,
                'beneficiary_name'=>$payment->method->beneficiary_name,'destination_label'=>$payment->method->destination_label,'destination_value'=>$payment->method->destination_value,
                'instructions_ar'=>$payment->method->instructions_ar,'requires_sender_phone'=>$payment->method->requires_sender_phone,
            ]:null,'provider_reference'=>$payment->provider_reference,'sender_name'=>$payment->sender_name,'sender_phone'=>$payment->sender_phone,
            'has_proof'=>$payment->proof_path!==null,'proof_url'=>$payment->proof_path?'/api/finance/payments/'.$payment->id.'/proof':null,
            'review_note'=>$payment->review_note,'submitted_at'=>$payment->submitted_at?->toIso8601String(),'confirmed_at'=>$payment->confirmed_at?->toIso8601String(),
        ];
    }

    private function receivableData(PropertyPlatformReceivable $r): array
    {
        $remaining=round(max(0,(float)$r->amount_total-(float)$r->amount_paid),2);
        return ['id'=>$r->id,'reference'=>$r->reference,'property_id'=>$r->property_id,'amount_total'=>(float)$r->amount_total,'amount_paid'=>(float)$r->amount_paid,'remaining_amount'=>$remaining,'currency'=>$r->currency,'status'=>$r->status,'confirmed_direct_at'=>$r->confirmed_direct_at?->toIso8601String(),'due_at'=>$r->due_at?->toIso8601String(),'overdue'=>$remaining>0&&$r->due_at&&now()->gte($r->due_at)];
    }
}
