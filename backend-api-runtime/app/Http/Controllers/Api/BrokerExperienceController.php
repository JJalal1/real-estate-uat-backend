<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\BrokerAvailabilityService;
use App\Models\BrokerCustomerFollowup;
use App\Services\BrokerCustomerFollowupService;
use Carbon\Carbon;
use App\Services\BrokerDealService;
use App\Services\BrokerRankingService;
use App\Services\CloudAssetStorageService;
use App\Services\PropertyFinancialService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

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
        $v = $request->validate([
            'governorate' => ['nullable', 'string', 'max:120'], 'region_only' => ['nullable', 'boolean'],
            'search' => ['nullable', 'string', 'max:120'], 'specialty' => ['nullable', 'string', 'max:120'],
            'account_type' => ['nullable', Rule::in(['broker', 'office'])], 'min_rating' => ['nullable', 'numeric', 'between:0,5'],
            'page' => ['nullable', 'integer', 'min:1'], 'per_page' => ['nullable', 'integer', 'between:1,30'],
        ]);
        $query = $this->ranking->query($v['governorate'] ?? null);
        if (! empty($v['governorate']) && ($v['region_only'] ?? false)) {
            $aliases = in_array($v['governorate'], ['صنعاء', 'أمانة العاصمة'], true) ? ['صنعاء', 'أمانة العاصمة'] : [$v['governorate']];
            $query->whereHas('accountVerificationProfile', function ($profile) use ($aliases): void {
                $profile->where(function ($region) use ($aliases): void {
                    foreach ($aliases as $name) $region->orWhere('details->governorate', $name)->orWhereJsonContains('details->work_areas', $name);
                });
            });
        }
        if (! empty($v['account_type'])) $query->whereHas('accountVerificationProfile', fn ($profile) => $profile->where('type', $v['account_type']));
        if (! empty($v['specialty'])) $query->whereHas('accountVerificationProfile', fn ($profile) => $profile->whereJsonContains('details->specialties', trim($v['specialty'])));
        if (! empty($v['search'])) {
            $term = '%'.str_replace(['%', '_'], ['\\%', '\\_'], trim($v['search'])).'%';
            $query->where(function ($name) use ($term): void {
                $name->where('users.name', 'like', $term)->orWhereHas('accountVerificationProfile', fn ($profile) =>
                    $profile->where('type', 'office')->where('details->office_name', 'like', $term));
            });
        }
        if (($v['min_rating'] ?? 0) > 0) $query->where('customer_rating.rating_average', '>=', (float) $v['min_rating']);
        $page = $query->paginate((int) ($v['per_page'] ?? 15));
        return response()->json(['data'=>collect($page->items())->map(fn ($u) => $this->ranking->publicData($u))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total(),'governorate'=>$v['governorate'] ?? null]]);
    }

    public function publicProfile(Request $request, User $advertiser): JsonResponse
    {
        $profile=$this->ranking->query(null, false, true)->where('users.id',$advertiser->id)->firstOrFail();
        return response()->json(['data'=>$this->ranking->publicData($profile)]);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        $actor=$this->advertiser($request);
        $v=$request->validate(['bio'=>['nullable','string','max:900']]);
        $actor->forceFill(['public_professional_bio'=>trim((string)($v['bio'] ?? '')) ?: null])->save();
        return response()->json(['data'=>['bio'=>$actor->public_professional_bio]]);
    }

    public function uploadPhoto(Request $request, CloudAssetStorageService $storage): JsonResponse
    {
        $actor=$this->advertiser($request);
        $request->validate(['photo'=>['required','file','image','mimes:jpg,jpeg,png,webp','max:5120']]);
        // A separate, explicitly uploaded public photo; verification evidence is never reused.
        $path=$storage->storePublic($request->file('photo'),'professional-photos/'.$actor->id);
        try {
            $old=DB::transaction(function () use ($actor,$path) {
                $locked=User::query()->lockForUpdate()->findOrFail($actor->id);
                $old=$locked->public_professional_photo_path;
                $locked->forceFill(['public_professional_photo_path'=>$path])->save();
                return $old;
            });
        } catch (\Throwable $e) { $storage->deletePublic($path); throw $e; }
        if ($old) $storage->deletePublic($old);
        $this->audit->record($actor,'broker.public_photo_updated',$actor,[],$request,$actor->id);
        return response()->json(['data'=>['uploaded'=>true]]);
    }

    public function photo(User $advertiser, CloudAssetStorageService $storage)
    {
        abort_unless($advertiser->isActive() && $advertiser->hasApprovedVerificationProfile() && $advertiser->public_professional_photo_path,404);
        return $storage->responsePublic($advertiser->public_professional_photo_path,null,['Cache-Control'=>'public, max-age=3600','X-Content-Type-Options'=>'nosniff']);
    }

    public function workspace(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $original=app(ProfessionalWorkspaceController::class)->show($request)->getData(true)['data'];
        $own=Property::query()->withoutGlobalScopes()->where('user_id',$actor->id);
        $threads=$this->customerQuery($actor);
        $unread=DB::table('private_messages as m')
            ->join('message_thread_participants as p',fn ($join) => $join->on('p.thread_id','=','m.thread_id')->where('p.user_id','=',$actor->id))
            ->whereIn('m.thread_id',(clone $threads)->select('message_threads.id'))->where('m.sender_user_id','<>',$actor->id)
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
        $original['needs_attention']['customer_followups_due']=BrokerCustomerFollowup::query()->where('user_id',$actor->id)->where('remind_at','<=',now())->whereIn('message_thread_id',(clone $threads)->select('message_threads.id'))->count();
        $original['needs_attention']['availability_count']=$freshness;
        $original['needs_attention']['pending_deal_count']=BrokerDealOutcome::query()->where('advertiser_user_id',$actor->id)->whereIn('status',['pending_customer','disputed'])->count();
        $original['financial_summary']=$this->finance->financialSummaryFor($actor);
        $original['best_listing']=(clone $own)->where('status','published')->orderByDesc('view_count')->first(['id','title','view_count']);
        return response()->json(['data'=>$original]);
    }

    public function customers(Request $request): JsonResponse
    {
        $actor=$request->filled('property_id') ? $this->advertiser($request) : $this->professional($request);
        $v=$request->validate(['stage'=>['nullable',Rule::in(['new','contacted','viewing','not_interested','completed'])],
            'filter'=>['nullable',Rule::in(['all','unread','followup_due'])], 'page'=>['nullable','integer','min:1'],'property_id'=>['nullable','integer','min:1']]);
        $query=$this->customerQuery($actor)->with(['property:id,title,status,availability_status','participants'])
            ->select('message_threads.*')->selectSub($this->unreadMessages($actor)->selectRaw('COUNT(*)'), 'unread_count');
        if (!empty($v['stage'])) $query->where('lead_stage',$v['stage']);
        if (!empty($v['property_id'])) $query->where('property_id',$v['property_id']);
        if (($v['filter'] ?? null) === 'unread') $query->whereExists($this->unreadMessages($actor)->selectRaw('1'));
        if (($v['filter'] ?? null) === 'followup_due') $query->whereIn('message_threads.id', BrokerCustomerFollowup::query()
            ->where('user_id',$actor->id)->whereNotNull('remind_at')->where('remind_at','<=',now())->select('message_thread_id'));
        $page=$query->orderByDesc('last_message_at')->orderByDesc('id')->paginate(30);
        $rows=collect($page->items());
        $users=User::query()->whereIn('id',$rows->pluck('started_by_user_id'))->get(['id','name'])->keyBy('id');
        $outcomes=BrokerDealOutcome::query()->whereIn('message_thread_id',$rows->pluck('id'))->get()->keyBy('message_thread_id');
        $followups=BrokerCustomerFollowup::query()->where('user_id',$actor->id)->whereIn('message_thread_id',$rows->pluck('id'))->get()->keyBy('message_thread_id');
        return response()->json(['data'=>$rows->map(fn ($thread) => [
            'thread_id'=>$thread->id,'customer_id'=>$thread->started_by_user_id,'customer_name'=>$users->get($thread->started_by_user_id)?->name ?? 'عميل',
            'property_id'=>$thread->property_id,'property_title'=>$thread->property?->title,'stage'=>$thread->lead_stage,
            'last_message_at'=>$thread->last_message_at?->toIso8601String(),
            'unread_count'=>(int)$thread->unread_count,
            'followup'=>$this->followupData($followups->get($thread->id)),
            'deal'=>$outcomes->has($thread->id) ? $this->outcomeData($outcomes->get($thread->id),$actor) : null,
        ])->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage()]]);
    }

    public function customerFollowup(Request $request, MessageThread $thread): JsonResponse
    {
        $actor=$this->professional($request);
        $this->customerQuery($actor)->whereKey($thread->id)->firstOrFail();
        return response()->json(['data'=>$this->followupData(BrokerCustomerFollowup::query()->where('user_id',$actor->id)->where('message_thread_id',$thread->id)->first())]);
    }

    public function saveCustomerFollowup(Request $request, MessageThread $thread, BrokerCustomerFollowupService $service): JsonResponse
    {
        $actor=$this->professional($request);
        $v=$request->validate(['private_note'=>['sometimes','nullable','string','max:1500'], 'remind_at'=>['sometimes','nullable','date']]);
        return DB::transaction(function () use ($actor,$thread,$v,$service,$request): JsonResponse {
            $this->customerQuery($actor)->whereKey($thread->id)->lockForUpdate()->firstOrFail();
            $row=BrokerCustomerFollowup::query()->firstOrCreate(['user_id'=>$actor->id,'message_thread_id'=>$thread->id]);
            if (array_key_exists('remind_at',$v)) {
                $date=isset($v['remind_at']) ? Carbon::parse($v['remind_at'])->utc() : null;
                $same=$date && $row->remind_at && $date->equalTo($row->remind_at);
                if ($date && !$same && ($date->lte(now()) || $date->gt(now()->addYear()))) {
                    throw ValidationException::withMessages(['remind_at'=>['اختر موعدًا قادمًا خلال سنة.']]);
                }
                if (!$same) {
                    $row->forceFill(['remind_at'=>$date,'reminded_at'=>null]);
                    $service->clearNotice((int)$actor->id,(int)$thread->id);
                }
            }
            if (array_key_exists('private_note',$v)) $row->private_note=trim((string)$v['private_note']) ?: null;
            $row->save();
            $this->audit->record($actor,'broker.customer_followup_updated',$thread,['remind_at'=>$row->remind_at?->toIso8601String()],$request,$thread->started_by_user_id);
            return response()->json(['data'=>$this->followupData($row)]);
        });
    }

    private function followupData(?BrokerCustomerFollowup $row): array
    {
        return ['private_note'=>$row?->private_note,'remind_at'=>$row?->remind_at?->toIso8601String(),
            'is_due'=>$row?->remind_at?->lte(now()) ?? false];
    }

    private function unreadMessages(User $actor)
    {
        return DB::table('private_messages as unread_m')->join('message_thread_participants as read_p',fn ($join) =>
            $join->on('read_p.thread_id','=','unread_m.thread_id')->where('read_p.user_id','=',$actor->id))
            ->whereColumn('unread_m.thread_id','message_threads.id')->where('unread_m.sender_user_id','<>',$actor->id)
            ->where(fn ($q) => $q->whereNull('read_p.last_read_message_id')->orWhereColumn('unread_m.id','>','read_p.last_read_message_id'));
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
        $actor=$this->advertiser($request);
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
        $rows=$this->availability->change($this->advertiser($request),$v['property_ids'],$v['state'],$request);
        return response()->json(['data'=>['updated'=>count($rows),'property_ids'=>array_map(fn ($p) => $p->id,$rows),'state'=>$v['state']]]);
    }

    public function reportDeal(Request $request, MessageThread $thread): JsonResponse
    {
        $v=$request->validate(['basis_amount'=>['nullable','numeric','gt:0','max:9999999999999']]);
        $outcome=$this->deals->report($this->advertiser($request),$thread,isset($v['basis_amount']) ? (float)$v['basis_amount'] : null,$request);
        return response()->json(['data'=>$this->outcomeData($outcome,$request->user())],201);
    }

    public function activity(Request $request): JsonResponse
    {
        $actor=$request->user();
        $v=$request->validate(['thread_id'=>['nullable','integer','min:1'],'page'=>['nullable','integer','min:1']]);
        $page=BrokerDealOutcome::query()->where(fn ($q) => $q->where('advertiser_user_id',$actor->id)->orWhere('customer_user_id',$actor->id))
            ->when(isset($v['thread_id']),fn ($q) => $q->where('message_thread_id',$v['thread_id']))->latest('id')->paginate(30);
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
        $actor=$this->advertiser($request);
        $rows=PropertyPlatformReceivable::query()->where('advertiser_user_id',$actor->id)->with('financialTerm.property')->latest('id')->limit(250)->get();
        // Summaries cover the full account even when the visible history is bounded.
        $summary=PropertyPlatformReceivable::query()->where('advertiser_user_id',$actor->id)->groupBy('currency')->select('currency')
            ->selectRaw('SUM(amount_paid) AS paid')
            ->selectRaw("SUM(CASE WHEN status IN ('open','under_review','overdue','disputed') AND amount_total > amount_paid THEN amount_total - amount_paid ELSE 0 END) AS open")
            ->get()->map(fn ($balance) => ['currency'=>$balance->currency,'paid'=>round((float)$balance->paid,2),'open'=>round((float)$balance->open,2)])->values();
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
        abort_if($this->finance->hasOverdueReceivable((int)$property->user_id),404);
        $v=$request->validate(['viewer_key'=>['required','string','min:16','max:128']]);
        $viewer=$this->tokens->authenticate($request,false);
        if ($viewer && (int)$viewer->id === (int)$property->user_id) return response()->json(['data'=>['recorded'=>false]]);
        $hash=hash_hmac('sha256',$viewer ? 'user:'.$viewer->id : 'device:'.$v['viewer_key'],(string)config('app.key'));
        $recorded=DB::transaction(function () use ($property,$hash) {
            $recorded=DB::table('property_listing_views')->insertOrIgnore(['property_id'=>$property->id,'viewer_hash'=>$hash,'view_date'=>now()->toDateString(),'created_at'=>now()]);
            if ($recorded) DB::table('properties')->where('id',$property->id)->increment('view_count');
            return $recorded;
        });
        return response()->json(['data'=>['recorded'=>(bool)$recorded]]);
    }

    public function resolveDeal(Request $request, SupportTask $task): JsonResponse
    {
        $v=$request->validate(['decision'=>['required',Rule::in(['retry','cancel'])],'note'=>['required','string','min:5','max:2000'],'acting_as_agent'=>['nullable','boolean']]);
        $result=$this->deals->resolveSupport($request->user(),$task,$v['decision'],$v['note'],$request,(bool)($v['acting_as_agent'] ?? false));
        return response()->json(['data'=>['id'=>$result->id,'status'=>$result->status]]);
    }

    private function advertiser(Request $request): User
    {
        $actor=$request->user();
        abort_unless($actor && $actor->hasApprovedVerificationProfile(),403);
        return $actor;
    }

    private function professional(Request $request): User
    {
        $actor=$this->advertiser($request);
        abort_unless(app(\App\Services\ListingAccessService::class)->isProfessional($actor),403);
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
            'can_rate'=>(int)$viewer->id === (int)$outcome->customer_user_id && $outcome->status === 'confirmed',
            'can_view_support_case'=>(int)$viewer->id === (int)$outcome->customer_user_id,'support_case_id'=>$outcome->support_case_id];
    }
}
