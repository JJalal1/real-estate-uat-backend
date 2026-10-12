<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\BrokerAvailabilityService;
use App\Services\BrokerDealService;
use App\Services\BrokerRankingService;
use App\Services\PropertyFinancialService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class BrokerExperienceController extends Controller
{
    public function __construct(
        private readonly BrokerAvailabilityService $availability,
        private readonly BrokerDealService $deals,
        private readonly BrokerRankingService $ranking,
        private readonly PropertyFinancialService $finance,
        private readonly ApiTokenService $tokens,
        private readonly AuditLogService $audit,
    ) {}

    public function directory(Request $request): JsonResponse
    {
        $v=$request->validate(['governorate'=>['nullable','string','max:120'],'page'=>['nullable','integer','min:1'],'per_page'=>['nullable','integer','between:1,30']]);
        $page=$this->ranking->query($v['governorate'] ?? null)->paginate((int)($v['per_page'] ?? 15));
        return response()->json(['data'=>collect($page->items())->map(fn ($u) => $this->ranking->publicData($u))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total(),'governorate'=>$v['governorate'] ?? null]]);
    }

    public function publicProfile(Request $request, User $advertiser): JsonResponse
    {
        $profile=$this->ranking->query(null, false)->where('users.id',$advertiser->id)->firstOrFail();
        return response()->json(['data'=>$this->ranking->publicData($profile)]);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $v=$request->validate(['bio'=>['nullable','string','max:900']]);
        $actor->forceFill(['public_professional_bio'=>trim((string)($v['bio'] ?? '')) ?: null])->save();
        return response()->json(['data'=>['bio'=>$actor->public_professional_bio]]);
    }

    public function workspace(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $original=app(ProfessionalWorkspaceController::class)->show($request)->getData(true)['data'];
        $own=Property::query()->withoutGlobalScopes()->where('user_id',$actor->id);
        $threads=$this->customerQuery($actor);
        $ids=(clone $threads)->pluck('id');
        $unread=$ids->isEmpty() ? 0 : DB::table('private_messages as m')
            ->join('message_thread_participants as p',fn ($join) => $join->on('p.thread_id','=','m.thread_id')->where('p.user_id','=',$actor->id))
            ->whereIn('m.thread_id',$ids)->where('m.sender_user_id','<>',$actor->id)
            ->where(fn ($q) => $q->whereNull('p.last_read_message_id')->orWhereColumn('m.id','>','p.last_read_message_id'))
            ->distinct()->count('m.thread_id');
        $completed=BrokerDealOutcome::query()->where('advertiser_user_id',$actor->id)->where('status','confirmed')->count();
        $freshness=(clone $own)->where('status','published')->where(fn ($q) => $q->where('availability_status','confirmation_paused')
            ->orWhere(fn ($n) => $n->where('availability_status','available')->where('availability_due_at','<=',now())))->count();
        $profile=$this->ranking->query(null,false)->where('users.id',$actor->id)->first();
        $original['broker_profile']=$profile ? $this->ranking->publicData($profile) : null;
        $original['customer_activity']['unread_conversations']=$unread;
        $original['customer_activity']['completed_deals']=$completed;
        $original['customer_activity']['new_customers_this_week']=(clone $threads)->where('message_threads.created_at','>=',now()->startOfWeek())->count();
        $original['needs_attention']['availability_count']=$freshness;
        $original['needs_attention']['pending_deal_count']=BrokerDealOutcome::query()->where('advertiser_user_id',$actor->id)->whereIn('status',['pending_customer','disputed'])->count();
        $original['financial_summary']=$this->finance->financialSummaryFor($actor);
        $original['best_listing']=(clone $own)->where('status','published')->orderByDesc('view_count')->first(['id','title','view_count']);
        return response()->json(['data'=>$original]);
    }

    public function customers(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $v=$request->validate(['stage'=>['nullable',Rule::in(['new','contacted','viewing','not_interested','completed'])],'page'=>['nullable','integer','min:1']]);
        $query=$this->customerQuery($actor)->with(['property:id,title,status,availability_status','participants']);
        if (!empty($v['stage'])) $query->where('lead_stage',$v['stage']);
        $page=$query->orderByDesc('last_message_at')->orderByDesc('id')->paginate(30);
        $rows=collect($page->items());
        $users=User::query()->whereIn('id',$rows->pluck('started_by_user_id'))->get(['id','name'])->keyBy('id');
        $outcomes=BrokerDealOutcome::query()->whereIn('message_thread_id',$rows->pluck('id'))->get()->keyBy('message_thread_id');
        return response()->json(['data'=>$rows->map(fn ($thread) => [
            'thread_id'=>$thread->id,'customer_id'=>$thread->started_by_user_id,'customer_name'=>$users->get($thread->started_by_user_id)?->name ?? 'عميل',
            'property_id'=>$thread->property_id,'property_title'=>$thread->property?->title,'stage'=>$thread->lead_stage,
            'last_message_at'=>$thread->last_message_at?->toIso8601String(),
            'deal'=>$outcomes->has($thread->id) ? $this->outcomeData($outcomes->get($thread->id),$actor) : null,
        ])->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage()]]);
    }

    public function updateCustomer(Request $request, MessageThread $thread): JsonResponse
    {
        $actor=$this->professional($request);
        $v=$request->validate(['stage'=>['required',Rule::in(['new','contacted','viewing','not_interested'])]]);
        return DB::transaction(function () use ($actor,$thread,$v,$request): JsonResponse {
            $locked=$this->customerQuery($actor)->whereKey($thread->id)->lockForUpdate()->firstOrFail();
            abort_if(BrokerDealOutcome::query()->where('message_thread_id',$locked->id)->where('status','confirmed')->exists(),409,'العميل مرتبط بصفقة مكتملة مؤكدة.');
            $locked->forceFill(['lead_stage'=>$v['stage'],'lead_updated_at'=>now()])->save();
            $this->audit->record($actor,'broker.customer_stage_changed',$locked,['stage'=>$v['stage']],$request,$locked->started_by_user_id);
            return response()->json(['data'=>['thread_id'=>$locked->id,'stage'=>$locked->lead_stage]]);
        });
    }

    public function listingAvailability(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $rows=Property::query()->withoutGlobalScopes()->where('user_id',$actor->id)->where('status','published')
            ->whereNotIn('availability_status',['sold','rented'])->orderBy('availability_due_at')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn ($p) => [
            'id'=>$p->id,'title'=>$p->title,'purpose'=>$p->purpose,'availability_status'=>$p->availability_status,
            'confirmed_at'=>$p->availability_confirmed_at?->toIso8601String(),'due_at'=>$p->availability_due_at?->toIso8601String(),
            'notified_at'=>$p->availability_notified_at?->toIso8601String(),'needs_confirmation'=>$p->availability_due_at?->isPast() ?? false,
        ])->values()]);
    }

    public function changeAvailability(Request $request): JsonResponse
    {
        $v=$request->validate(['property_ids'=>['required','array','min:1','max:100'],'property_ids.*'=>['required','integer','distinct','min:1'],
            'state'=>['required',Rule::in(['available','paused','sold','rented'])]]);
        $rows=$this->availability->change($this->professional($request),$v['property_ids'],$v['state'],$request);
        return response()->json(['data'=>['updated'=>count($rows),'property_ids'=>array_map(fn ($p) => $p->id,$rows),'state'=>$v['state']]]);
    }

    public function reportDeal(Request $request, MessageThread $thread): JsonResponse
    {
        $v=$request->validate(['basis_amount'=>['nullable','numeric','gt:0','max:9999999999999']]);
        $outcome=$this->deals->report($this->professional($request),$thread,isset($v['basis_amount']) ? (float)$v['basis_amount'] : null,$request);
        return response()->json(['data'=>$this->outcomeData($outcome,$request->user())],201);
    }

    public function activity(Request $request): JsonResponse
    {
        $actor=$request->user();
        $page=BrokerDealOutcome::query()->where(fn ($q) => $q->where('advertiser_user_id',$actor->id)->orWhere('customer_user_id',$actor->id))
            ->latest('id')->paginate(30);
        return response()->json(['data'=>collect($page->items())->map(fn ($o) => $this->outcomeData($o,$actor))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage()]]);
    }

    public function deal(Request $request, BrokerDealOutcome $outcome): JsonResponse
    {
        $actor=$request->user();
        abort_unless(in_array((int)$actor->id,[(int)$outcome->advertiser_user_id,(int)$outcome->customer_user_id],true),404);
        return response()->json(['data'=>$this->outcomeData($outcome,$actor)]);
    }

    public function decideDeal(Request $request, BrokerDealOutcome $outcome): JsonResponse
    {
        $v=$request->validate(['confirmed'=>['required','boolean']]);
        $result=$this->deals->decide($request->user(),$outcome,(bool)$v['confirmed'],$request);
        return response()->json(['data'=>$this->outcomeData($result,$request->user())]);
    }

    public function finance(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $rows=PropertyPlatformReceivable::query()->where('advertiser_user_id',$actor->id)->with('financialTerm.property')->latest('id')->limit(250)->get();
        $summary=[];
        foreach ($rows->groupBy('currency') as $currency=>$group) {
            $summary[]=['currency'=>$currency,'paid'=>round((float)$group->sum('amount_paid'),2),
                'open'=>round((float)$group->filter(fn ($r) => in_array($r->status,['open','under_review','overdue','disputed'],true))
                    ->sum(fn ($r) => max(0,$r->amount_total-$r->amount_paid)),2)];
        }
        return response()->json(['data'=>['balances'=>$summary,'policy'=>$this->finance->financialSummaryFor($actor),
            'receivables'=>$rows->map(fn ($r) => ['id'=>$r->id,'reference'=>$r->reference,'property_id'=>$r->property_id,
                'property_title'=>$r->financialTerm?->property?->title,'transaction_type'=>$r->financialTerm?->transaction_type,
                'basis_amount'=>$r->financialTerm?->base_amount,'sai_amount'=>$r->financialTerm?->sai_total_amount,
                'amount_total'=>$r->amount_total,'amount_paid'=>$r->amount_paid,'remaining_amount'=>round(max(0,$r->amount_total-$r->amount_paid),2),
                'currency'=>$r->currency,'status'=>$r->status,'due_at'=>$r->due_at?->toIso8601String()])->values()]]);
    }

    public function recordView(Request $request, Property $property): JsonResponse
    {
        abort_unless($property->isPubliclyAvailable(),404);
        $v=$request->validate(['viewer_key'=>['required','string','min:16','max:128']]);
        $viewer=$this->tokens->authenticate($request,false);
        if ($viewer && (int)$viewer->id === (int)$property->user_id) return response()->json(['data'=>['recorded'=>false]]);
        $hash=hash_hmac('sha256',$viewer ? 'user:'.$viewer->id : 'device:'.$v['viewer_key'],(string)config('app.key'));
        $recorded=DB::table('property_listing_views')->insertOrIgnore(['property_id'=>$property->id,'viewer_hash'=>$hash,'view_date'=>now()->toDateString(),'created_at'=>now()]);
        if ($recorded) DB::table('properties')->where('id',$property->id)->increment('view_count');
        return response()->json(['data'=>['recorded'=>(bool)$recorded]]);
    }

    private function professional(Request $request): User
    {
        $actor=$request->user();
        abort_unless($actor && $actor->hasApprovedVerificationProfile(),403);
        return $actor;
    }

    private function customerQuery(User $actor)
    {
        return MessageThread::query()->whereHas('property',fn ($q) => $q->withoutGlobalScopes()->where('user_id',$actor->id))
            ->where('started_by_user_id','<>',$actor->id)->whereHas('participants',fn ($q) => $q->where('user_id',$actor->id));
    }

    private function outcomeData(BrokerDealOutcome $outcome, User $viewer): array
    {
        return ['id'=>$outcome->id,'reference'=>$outcome->reference,'property_id'=>$outcome->property_id,
            'thread_id'=>$outcome->message_thread_id,'advertiser_id'=>$outcome->advertiser_user_id,'customer_id'=>$outcome->customer_user_id,
            'status'=>$outcome->status,'transaction_type'=>$outcome->transaction_type,'basis_amount'=>$outcome->basis_amount,'currency'=>$outcome->currency,
            'property_title'=>$outcome->snapshot['property_title'],'customer_name'=>$outcome->snapshot['customer_name'],
            'advertiser_name'=>$outcome->snapshot['advertiser_name'],'confirmed_at'=>$outcome->confirmed_at?->toIso8601String(),
            'can_confirm'=>(int)$viewer->id === (int)$outcome->customer_user_id && $outcome->status === 'pending_customer',
            'can_rate'=>(int)$viewer->id === (int)$outcome->customer_user_id && $outcome->status === 'confirmed','support_case_id'=>$outcome->support_case_id];
    }
}
