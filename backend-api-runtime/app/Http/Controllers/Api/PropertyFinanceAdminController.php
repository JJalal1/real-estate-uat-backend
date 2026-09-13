<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PropertyPaymentMethod;
use App\Models\User;
use App\Services\AuditLogService;
use Illuminate\Database\Query\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class PropertyFinanceAdminController extends Controller
{
    public function __construct(private readonly AuditLogService $audit) {}

    public function summary(Request $request): JsonResponse
    {
        $this->assertView($request->user());
        $filters=$this->filters($request);
        $terms=$this->termsQuery($filters);
        $termIds=(clone $terms)->pluck('d.id');
        $advertiserIds=(clone $terms)->pluck('d.advertiser_user_id')->unique()->values();

        $receivables=DB::table('property_platform_receivables as r')->whereIn('r.deal_financial_term_id',$termIds);
        $openReceivables=(clone $receivables)->whereIn('r.status',['open','under_review','overdue','disputed'])->whereColumn('r.amount_paid','<','r.amount_total');
        $payouts=DB::table('property_payouts as po')->whereIn('po.deal_financial_term_id',$termIds);
        $payments=DB::table('property_payments as pay')->whereIn('pay.deal_financial_term_id',$termIds);

        $data=[
            'gross_transaction_value'=>(float)(clone $terms)->sum('d.base_amount'),
            'total_sai_amount'=>(float)(clone $terms)->sum('d.sai_total_amount'),
            'platform_entitlement_amount'=>(float)(clone $terms)->sum('d.platform_share_amount'),
            'advertiser_sai_entitlement_amount'=>(float)(clone $terms)->sum('d.advertiser_sai_share_amount'),
            'payments_waiting_review'=>(clone $payments)->whereIn('pay.status',['proof_submitted','under_review'])->count(),
            'confirmed_payments_amount'=>(float)(clone $payments)->where('pay.status','confirmed')->sum('pay.required_amount'),
            'open_receivables_amount'=>(float)(clone $openReceivables)->selectRaw('COALESCE(SUM(r.amount_total-r.amount_paid),0) total')->value('total'),
            'overdue_receivables_amount'=>(float)(clone $openReceivables)->where('r.due_at','<=',now())->selectRaw('COALESCE(SUM(r.amount_total-r.amount_paid),0) total')->value('total'),
            'overdue_accounts'=>(clone $openReceivables)->where('r.due_at','<=',now())->distinct('r.advertiser_user_id')->count('r.advertiser_user_id'),
            'pending_payouts_amount'=>(float)(clone $payouts)->where('po.status','pending')->sum('po.amount'),
            'paid_payouts_amount'=>(float)(clone $payouts)->where('po.status','paid')->sum('po.amount'),
            'open_disputes'=>DB::table('property_financial_disputes')->whereIn('deal_financial_term_id',$termIds)->where('status','open')->count(),
            'active_financial_holds'=>DB::table('property_financial_holds')->whereIn('user_id',$advertiserIds)->whereNull('released_at')->count(),
            'hidden_published_listings'=>DB::table('properties')->whereIn('user_id',$advertiserIds)->where('status','published')->whereNotNull('financial_hold_at')->count(),
            'pending_refunds_amount'=>(float)DB::table('property_refunds as rf')->join('property_payments as pay','pay.id','=','rf.property_payment_id')->whereIn('pay.deal_financial_term_id',$termIds)->where('rf.status','pending')->sum('rf.amount'),
        ];
        return response()->json(['data'=>$data]);
    }

    public function workspace(Request $request): JsonResponse
    {
        $this->assertView($request->user());
        $filters=$this->filters($request);
        $terms=$this->termsQuery($filters);
        $termIds=(clone $terms)->pluck('d.id');
        $advertiserIds=(clone $terms)->pluck('d.advertiser_user_id')->unique()->values();

        $deals=(clone $terms)
            ->leftJoin('users as buyer','buyer.id','=','d.buyer_user_id')
            ->leftJoin('users as advertiser','advertiser.id','=','d.advertiser_user_id')
            ->select(['d.id','d.property_agreement_id','d.property_id','p.title as property_title','d.transaction_type','d.advertiser_type','d.currency','d.base_amount','d.sai_total_amount','d.sai_payer','d.platform_share_amount','d.advertiser_sai_share_amount','d.frozen_at','buyer.name as buyer_name','advertiser.name as advertiser_name','g.name_ar as governorate_name'])
            ->orderByDesc('d.id')->limit(250)->get();

        $payments=DB::table('property_payments as pay')
            ->join('property_deal_financial_terms as d','d.id','=','pay.deal_financial_term_id')
            ->leftJoin('property_payment_methods as m','m.id','=','pay.payment_method_id')
            ->leftJoin('properties as p','p.id','=','pay.property_id')
            ->whereIn('pay.deal_financial_term_id',$termIds)
            ->select(['pay.id','pay.reference','pay.property_id','p.title as property_title','pay.mode','pay.status','pay.required_amount','pay.currency','m.name_ar as payment_method','pay.submitted_at','pay.reviewed_at','pay.confirmed_at','pay.created_at'])
            ->orderByDesc('pay.id')->limit(250)->get();

        $payouts=DB::table('property_payouts as po')
            ->leftJoin('users as u','u.id','=','po.advertiser_user_id')
            ->whereIn('po.deal_financial_term_id',$termIds)
            ->select(['po.id','po.reference','po.deal_financial_term_id','po.advertiser_user_id','u.name as advertiser_name','po.amount','po.currency','po.status','po.external_reference','po.paid_at','po.created_at'])
            ->orderByDesc('po.id')->limit(250)->get();

        $receivables=DB::table('property_platform_receivables as r')
            ->leftJoin('users as u','u.id','=','r.advertiser_user_id')
            ->leftJoin('properties as p','p.id','=','r.property_id')
            ->whereIn('r.deal_financial_term_id',$termIds)
            ->selectRaw('r.id,r.reference,r.deal_financial_term_id,r.property_id,p.title property_title,r.advertiser_user_id,u.name advertiser_name,r.amount_total,r.amount_paid,(r.amount_total-r.amount_paid) remaining_amount,r.currency,r.status,r.confirmed_direct_at,r.due_at,r.paid_at,r.created_at')
            ->orderByDesc('r.id')->limit(250)->get();

        $overdue=$receivables->filter(fn($r)=>(float)$r->remaining_amount>0 && $r->due_at && Carbon::parse($r->due_at)->lte(now()))->values();

        $holds=DB::table('property_financial_holds as h')
            ->leftJoin('users as u','u.id','=','h.user_id')
            ->whereIn('h.user_id',$advertiserIds)
            ->select(['h.id','h.user_id','u.name as advertiser_name','h.reason','h.source_type','h.source_id','h.started_at','h.released_at','h.release_reason','h.created_at'])
            ->orderByDesc('h.id')->limit(250)->get();

        $refunds=DB::table('property_refunds as rf')
            ->join('property_payments as pay','pay.id','=','rf.property_payment_id')
            ->leftJoin('users as u','u.id','=','rf.beneficiary_user_id')
            ->whereIn('pay.deal_financial_term_id',$termIds)
            ->select(['rf.id','rf.reference','rf.property_payment_id','rf.beneficiary_user_id','u.name as beneficiary_name','rf.amount','rf.currency','rf.status','rf.reason','rf.refunded_at','rf.created_at'])
            ->orderByDesc('rf.id')->limit(250)->get();

        $disputes=DB::table('property_financial_disputes as fd')
            ->leftJoin('users as u','u.id','=','fd.opened_by_user_id')
            ->whereIn('fd.deal_financial_term_id',$termIds)
            ->select(['fd.id','fd.reference','fd.deal_financial_term_id','fd.opened_by_user_id','u.name as opened_by_name','fd.status','fd.reason','fd.resolution','fd.resolved_at','fd.created_at'])
            ->orderByDesc('fd.id')->limit(250)->get();

        $audit=DB::table('audit_logs as a')->leftJoin('users as u','u.id','=','a.actor_user_id')
            ->where(function(Builder $q):void{$q->where('a.action','like','finance.%')->orWhereIn('a.action',['listing.sai_attested','listing.financial_config_updated']);})
            ->select(['a.id','a.actor_user_id','u.name as actor_name','a.action','a.subject_type','a.subject_id','a.metadata','a.created_at'])
            ->orderByDesc('a.id')->limit(250)->get();

        return response()->json(['data'=>[
            'filters'=>$filters,
            'summary'=>$this->summary($request)->getData(true)['data'],
            'deals'=>$deals,'payments'=>$payments,'payouts'=>$payouts,'receivables'=>$receivables,'overdue'=>$overdue,
            'holds'=>$holds,'refunds'=>$refunds,'disputes'=>$disputes,'audit_log'=>$audit,
        ]]);
    }

    public function paymentMethods(Request $request): JsonResponse
    {
        $this->assertManage($request->user());
        return response()->json(['data'=>PropertyPaymentMethod::query()->orderBy('sort_order')->get()->map(fn(PropertyPaymentMethod $m)=>$this->methodData($m))->values()]);
    }

    public function updatePaymentMethod(Request $request, PropertyPaymentMethod $method): JsonResponse
    {
        /** @var User $actor */$actor=$request->user();$this->assertManage($actor);
        $validated=$request->validate([
            'name_ar'=>['sometimes','string','max:80'],'beneficiary_name'=>['sometimes','string','max:160'],
            'destination_label'=>['sometimes','string','max:80'],'destination_value'=>['sometimes','string','max:120'],
            'currency'=>['sometimes','string','size:3'],'min_amount'=>['nullable','numeric','min:0'],'max_amount'=>['nullable','numeric','min:0'],
            'allows_full_payment'=>['sometimes','boolean'],'allows_sai_only'=>['sometimes','boolean'],
            'instructions_ar'=>['nullable','string','max:2000'],'requires_sender_phone'=>['sometimes','boolean'],
            'requires_provider_reference'=>['sometimes','boolean'],'is_enabled'=>['sometimes','boolean'],'sort_order'=>['sometimes','integer','min:0','max:1000'],
        ]);
        if(isset($validated['currency']))$validated['currency']=strtoupper($validated['currency']);
        if(isset($validated['min_amount'],$validated['max_amount']) && $validated['max_amount']!==null && (float)$validated['max_amount']<(float)$validated['min_amount']){
            return response()->json(['message'=>'الحد الأعلى يجب أن يكون أكبر من أو يساوي الحد الأدنى.','errors'=>['max_amount'=>['الحد الأعلى غير صالح.']]],422);
        }
        $before=$this->methodData($method);
        $method->fill($validated)->save();
        $this->audit->record($actor,'finance.payment_method_updated',$method,['before'=>$before,'changed_fields'=>array_keys($validated)],$request);
        return response()->json(['message'=>'تم تحديث طريقة الدفع.','data'=>$this->methodData($method->fresh())]);
    }

    private function filters(Request $request): array
    {
        return $request->validate([
            'period'=>['nullable',Rule::in(['day','7d','30d','all'])],
            'transaction_type'=>['nullable',Rule::in(['sale','rent'])],
            'advertiser_type'=>['nullable',Rule::in(['owner','broker','office'])],
            'governorate_id'=>['nullable','integer','exists:governorates,id'],
        ]) + ['period'=>$request->input('period','30d')];
    }

    private function termsQuery(array $filters): Builder
    {
        $q=DB::table('property_deal_financial_terms as d')
            ->join('properties as p','p.id','=','d.property_id')
            ->leftJoin('geo_cells as gc','gc.id','=','p.geo_cell_id')
            ->leftJoin('governorates as g','g.id','=','gc.governorate_id');
        $period=$filters['period']??'30d';
        if($period==='day')$q->where('d.frozen_at','>=',now()->startOfDay());
        elseif($period==='7d')$q->where('d.frozen_at','>=',now()->subDays(7));
        elseif($period==='30d')$q->where('d.frozen_at','>=',now()->subDays(30));
        if(!empty($filters['transaction_type']))$q->where('d.transaction_type',$filters['transaction_type']);
        if(!empty($filters['advertiser_type']))$q->where('d.advertiser_type',$filters['advertiser_type']);
        if(!empty($filters['governorate_id']))$q->where('gc.governorate_id',(int)$filters['governorate_id']);
        return $q;
    }

    private function methodData(PropertyPaymentMethod $m): array
    {
        return [
            'id'=>$m->id,'key'=>$m->key,'name_ar'=>$m->name_ar,'asset_key'=>$m->asset_key,
            'beneficiary_name'=>$m->beneficiary_name,'destination_label'=>$m->destination_label,'destination_value'=>$m->destination_value,
            'currency'=>$m->currency,'min_amount'=>$m->min_amount,'max_amount'=>$m->max_amount,
            'allows_full_payment'=>$m->allows_full_payment,'allows_sai_only'=>$m->allows_sai_only,
            'instructions_ar'=>$m->instructions_ar,'requires_sender_phone'=>$m->requires_sender_phone,
            'requires_provider_reference'=>$m->requires_provider_reference,'is_enabled'=>$m->is_enabled,'sort_order'=>$m->sort_order,
        ];
    }

    private function assertView(?User $actor): void
    {
        abort_unless($actor && ($actor->is_platform_owner||$actor->hasRole('super_admin')||$actor->hasPermission('finance.view')||$actor->hasPermission('finance.manage')),403);
    }

    private function assertManage(?User $actor): void
    {
        abort_unless($actor && ($actor->is_platform_owner||$actor->hasRole('super_admin')||$actor->hasPermission('finance.manage')),403);
    }
}
