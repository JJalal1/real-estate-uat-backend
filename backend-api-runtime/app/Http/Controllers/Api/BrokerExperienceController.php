<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdvertiserRating;
use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\PrivateMessage;
use App\Models\Property;
use App\Models\PropertyDealFinancialTerm;
use App\Models\PropertyPayment;
use App\Models\PropertyPlatformReceivable;
use App\Models\PropertySaiTerm;
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
use App\Services\PropertyFinancialService;
use App\Services\UserNotificationService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class BrokerExperienceController extends Controller
{
    private const EDITABLE_CUSTOMER_STAGES = ['new', 'contacted', 'viewing', 'not_interested', 'appointment_set', 'reserved'];

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
            'search' => ['nullable', 'string', 'max:120'],
            'account_type' => ['nullable', Rule::in(['broker', 'office'])], 'min_rating' => ['nullable', 'numeric', 'between:0,5'],
            'page' => ['nullable', 'integer', 'min:1'], 'per_page' => ['nullable', 'integer', 'between:1,30'],
        ]);
        $query = $this->ranking->query($v['governorate'] ?? null);
        if (! empty($v['governorate']) && ($v['region_only'] ?? false)) {
            $query->whereRaw(BrokerRankingService::GOVERNORATE.' = ?', [$v['governorate']]);
        }
        if (! empty($v['account_type'])) {
            $query->whereRaw(BrokerRankingService::IS_OFFICE.($v['account_type'] === 'office' ? ' = TRUE' : ' = FALSE'));
        }
        if (! empty($v['search'])) {
            $term = '%'.str_replace(['%', '_'], ['\\%', '\\_'], trim($v['search'])).'%';
            $query->where(function ($name) use ($term): void {
                $name->where('users.name', 'like', $term)->orWhereRaw(BrokerRankingService::OFFICE_NAME.' LIKE ?', [$term]);
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
        $actor = $request->user(); // The route requires an authenticated, active account.
        $canManageProfile = $actor->canManageExistingListings() &&
            ($actor->hasMarketplaceProfessionalProfile() || $actor->hasApprovedVerificationProfile());
        if (! $canManageProfile) {
            // Saving an optional biography never enrolls the account as an advertiser.
            abort_unless(array_keys($request->all()) === ['bio'], 403);
        }
        $rules = ['bio' => ['sometimes', 'nullable', 'string', 'max:150']];
        if ($actor->hasMarketplaceProfessionalProfile()) {
            $rules += [
                'governorate' => ['sometimes', 'required', 'string', Rule::exists('governorates', 'name_ar')->where('is_active', true)],
                'is_office' => ['sometimes', 'boolean'], 'office_name' => [Rule::requiredIf($request->boolean('is_office')), 'nullable', 'string', 'max:140'],
            ];
        }
        $values = $request->validate($rules);
        $changes = [];
        if (array_key_exists('bio', $values)) $changes['public_professional_bio'] = $values['bio'];
        if (isset($values['governorate'])) $changes['marketplace_governorate'] = $values['governorate'];
        if (array_key_exists('is_office', $values)) {
            $changes['marketplace_is_office'] = $request->boolean('is_office');
            $changes['marketplace_office_name'] = $changes['marketplace_is_office'] ? $values['office_name'] : null;
        }
        $actor->forceFill($changes)->save();
        $identity = $canManageProfile ? $this->ranking->publicIdentity($actor) : [];
        return response()->json(['data' => $identity + ['bio' => $actor->public_professional_bio]]);
    }

    public function uploadPhoto(Request $request, \App\Services\ProfessionalPhotoService $photos): JsonResponse
    {
        $actor=$this->advertiser($request);
        abort_unless($actor->hasMarketplaceProfessionalProfile() || $actor->hasApprovedVerificationProfile(), 403);
        $request->validate(['photo'=>['required','file','image','mimes:jpg,jpeg,png,webp','max:5120']]);
        // A separate, explicitly uploaded public photo; verification evidence is never reused.
        $path=$photos->store($request->file('photo'), (int)$actor->id);
        try {
            $old=DB::transaction(function () use ($actor,$path) {
                $locked=User::query()->lockForUpdate()->findOrFail($actor->id);
                $old=$locked->public_professional_photo_path;
                $locked->forceFill(['public_professional_photo_path'=>$path])->save();
                return $old;
            });
        } catch (\Throwable $e) {
            try { $photos->remove($path); } catch (\Throwable $cleanup) { report($cleanup); }
            throw $e;
        }
        if ($old) $photos->remove($old);
        $this->audit->record($actor,'broker.public_photo_updated',$actor,[],$request,$actor->id);
        return response()->json(['data'=>['uploaded'=>true]]);
    }

    public function photo(User $advertiser, \App\Services\ProfessionalPhotoService $photos)
    {
        abort_unless($advertiser->isActive() && ($advertiser->hasMarketplaceProfessionalProfile() || $advertiser->hasApprovedVerificationProfile()) && $advertiser->public_professional_photo_path,404);
        return $photos->response($advertiser->public_professional_photo_path);
    }

    public function workspace(Request $request): JsonResponse
    {
        $actor=$this->professional($request);
        $original=app(ProfessionalWorkspaceController::class)->show($request)->getData(true)['data'];
        $threads=$this->customerQuery($actor);
        $unread=DB::table('private_messages as m')
            ->join('message_thread_participants as p',fn ($join) => $join->on('p.thread_id','=','m.thread_id')->where('p.user_id','=',$actor->id))
            ->whereIn('m.thread_id',(clone $threads)->select('message_threads.id'))->where('m.sender_user_id','<>',$actor->id)
            ->where(fn ($q) => $q->whereNull('p.last_read_message_id')->orWhereColumn('m.id','>','p.last_read_message_id'))
            ->distinct()->count('m.thread_id');
        $completed=BrokerDealOutcome::query()->where('advertiser_user_id',$actor->id)->where('status','confirmed')->count();
        $freshness=$this->availability->updateCandidates($actor, true)->count();
        $profile=$this->ranking->query(null,false)->where('users.id',$actor->id)->first();
        $original['broker_profile']=$profile ? $this->ranking->publicData($profile) : null;
        $original['customer_activity']['unread_conversations']=$unread;
        $original['customer_activity']['completed_deals']=$completed;
        $original['customer_activity']['new_customers_this_week']=(clone $threads)->where('message_threads.created_at','>=',now()->startOfWeek())->count();
        $original['needs_attention']['customer_followups_due']=BrokerCustomerFollowup::query()->where('user_id',$actor->id)->where('remind_at','<=',now())->whereIn('message_thread_id',(clone $threads)->select('message_threads.id'))->count();
        $original['needs_attention']['availability_count']=$freshness;
        $original['needs_attention']['pending_deal_count']=BrokerDealOutcome::query()->where('advertiser_user_id',$actor->id)->whereIn('status',['pending_customer','disputed'])->count();
        $original['needs_attention']['unseen_deal_count'] = BrokerDealOutcome::query()
            ->where('advertiser_user_id', $actor->id)
            ->whereColumn('advertiser_seen_revision', '<', 'advertiser_attention_revision')
            ->count();
        $original['needs_attention']['outstanding_receivables_count'] = PropertyPlatformReceivable::query()
            ->where('advertiser_user_id', $actor->id)
            ->whereIn('status', ['open', 'under_review', 'overdue', 'disputed'])
            ->whereColumn('amount_paid', '<', 'amount_total')
            ->count();
        $original['financial_summary']=$this->finance->financialSummaryFor($actor);
        $original['best_listing']=$this->availability->updateCandidates($actor, false)
            ->orderByDesc('view_count')->first(['id','title','view_count']);
        $original['achievements'] = $this->achievements($actor, $threads, $completed > 0);
        $original['capabilities'] = [
            'customer_stage_classification_v2' => true,
            'broker_deal_view_tracking' => true,
        ];
        return response()->json(['data'=>$original]);
    }

    private function achievements(User $actor, Builder $threads, bool $hasConfirmedDeal): array
    {
        $localNow = now('Asia/Aden');
        $weekStart = $localNow->copy()->startOfWeek()->utc();
        $monthStart = $localNow->copy()->startOfMonth()->utc();
        $replies = DB::table('private_messages as reply')
            ->selectRaw('1')
            ->whereColumn('reply.thread_id', 'message_threads.id')
            ->where('reply.sender_user_id', $actor->id)
            ->where('reply.created_at', '>=', $weekStart)
            ->whereExists($this->customerMessages()->whereColumn('inquiry.id', '<', 'reply.id'));

        return [
            'first_confirmed_deal' => $hasConfirmedDeal,
            'customers_replied_to_this_week' => (clone $threads)
                ->whereExists($replies)->distinct()->count('message_threads.started_by_user_id'),
            'customer_ratings_count' => AdvertiserRating::query()
                ->where('advertiser_user_id', $actor->id)->where('status', 'visible')
                ->confirmedCustomerRatings()->count(),
            'listing_inquiries_this_month' => (clone $threads)
                ->whereExists($this->customerMessages()->where('inquiry.created_at', '>=', $monthStart))
                ->whereNotExists($this->customerMessages()->where('inquiry.created_at', '<', $monthStart))
                ->count(),
        ];
    }

    private function customerMessages(): QueryBuilder
    {
        return DB::table('private_messages as inquiry')
            ->selectRaw('1')
            ->whereColumn('inquiry.thread_id', 'message_threads.id')
            ->whereColumn('inquiry.sender_user_id', 'message_threads.started_by_user_id')
            ->where(fn (QueryBuilder $message) => $message->whereNull('inquiry.client_message_id')
                ->orWhere('inquiry.client_message_id', 'not like', 'sys-call:%'));
    }

    public function customers(Request $request): JsonResponse
    {
        $actor=$request->filled('property_id') ? $this->advertiser($request) : $this->professional($request);
        $v=$request->validate(['stage'=>['nullable',Rule::in([...self::EDITABLE_CUSTOMER_STAGES, 'completed', 'unclassified'])],
            'filter'=>['nullable',Rule::in(['all','unread','followup_due'])], 'page'=>['nullable','integer','min:1'],
            'property_id'=>['nullable','integer','min:1'], 'include_other_threads'=>['sometimes','boolean']]);
        $includeOtherThreads = $request->boolean('include_other_threads')
            && empty($v['property_id'])
            && in_array($v['stage'] ?? null, [null, 'unclassified'], true)
            && ($v['filter'] ?? null) !== 'followup_due';
        $managed = $this->customerQuery($actor);
        $managedIds = (clone $managed)->select('message_threads.id');
        $query = ($includeOtherThreads
            ? MessageThread::query()->whereHas('participants', fn (Builder $p) => $p->where('user_id', $actor->id))
            : $managed)
            ->with(['property:id,title,status,availability_status','participants'])
            ->select('message_threads.*')->selectSub($this->unreadMessages($actor)->selectRaw('COUNT(*)'), 'unread_count');
        if ($includeOtherThreads) {
            $query->selectRaw(
                'CASE WHEN message_threads.id IN ('.$managedIds->toSql().') THEN 1 ELSE 0 END AS is_managed_customer',
                $managedIds->getBindings(),
            )->orderByDesc('is_managed_customer');
        }
        if (($v['stage'] ?? null) === 'unclassified') {
            $query->where(function (Builder $stage) use ($includeOtherThreads, $managedIds): void {
                $stage->whereNull('lead_stage')->orWhereIn('lead_stage', ['new', 'contacted', 'viewing']);
                if ($includeOtherThreads) {
                    $stage->orWhereNotIn('message_threads.id', $managedIds);
                }
            });
        } elseif (!empty($v['stage'])) {
            $query->where('lead_stage', $v['stage']);
        }
        if (!empty($v['property_id'])) $query->where('property_id',$v['property_id']);
        if (($v['filter'] ?? null) === 'unread') $query->whereExists($this->unreadMessages($actor)->selectRaw('1'));
        if (($v['filter'] ?? null) === 'followup_due') $query->whereIn('message_threads.id', BrokerCustomerFollowup::query()
            ->where('user_id',$actor->id)->whereNotNull('remind_at')->where('remind_at','<=',now())->select('message_thread_id'));
        $page=$query->orderByDesc('last_message_at')->orderByDesc('id')->paginate(30);
        $rows=collect($page->items());
        $latestTextIds = PrivateMessage::query()->whereIn('thread_id', $rows->pluck('id'))
            ->where(fn (Builder $message) => $message->whereNull('client_message_id')
                ->orWhere('client_message_id', 'not like', 'sys-call:%'))
            ->selectRaw('MAX(id)')->groupBy('thread_id');
        $lastTexts = PrivateMessage::query()->whereIn('id', $latestTextIds)
            ->get(['thread_id', 'sender_user_id', 'body', 'created_at'])->keyBy('thread_id');
        $isManaged = fn (MessageThread $thread) => !$includeOtherThreads || (int) $thread->is_managed_customer === 1;
        $managedPageIds = $rows->filter($isManaged)->pluck('id');
        $otherParticipants = $rows->mapWithKeys(fn (MessageThread $thread) => [
            $thread->id => $thread->participants->first(fn ($p) => (int) $p->user_id !== (int) $actor->id),
        ]);
        $customerIdFor = fn (MessageThread $thread) => $isManaged($thread)
            ? $thread->started_by_user_id : $otherParticipants->get($thread->id)?->user_id;
        $users = User::query()->whereIn('id', $rows->map($customerIdFor)->filter()->unique())
            ->get(['id', 'name'])->keyBy('id');
        $outcomes = BrokerDealOutcome::query()->whereIn('message_thread_id', $managedPageIds)
            ->get()->keyBy('message_thread_id');
        $followups = BrokerCustomerFollowup::query()->where('user_id', $actor->id)
            ->whereIn('message_thread_id', $managedPageIds)->get()->keyBy('message_thread_id');
        $data = $rows->map(function (MessageThread $thread) use (
            $actor, $isManaged, $customerIdFor, $otherParticipants, $users, $lastTexts, $followups, $outcomes,
        ): array {
            $managed = $isManaged($thread);
            $customerId = $customerIdFor($thread);
            $last = $lastTexts->get($thread->id);
            $outcome = $outcomes->get($thread->id);

            return [
                'thread_id' => $thread->id,
                'customer_id' => $customerId,
                'customer_name' => $users->get($customerId)?->name
                    ?? $otherParticipants->get($thread->id)?->user_name_snapshot ?? 'عميل',
                'property_id' => $thread->property_id,
                'property_title' => $thread->property?->title,
                'can_manage_customer' => $managed,
                'stage' => $managed ? $thread->lead_stage : null,
                'last_message_preview' => $last ? mb_substr($last->body, 0, 120) : null,
                'last_message_at' => $last?->created_at?->toIso8601String(),
                'last_message_is_mine' => (int) $last?->sender_user_id === (int) $actor->id,
                'unread_count' => (int) $thread->unread_count,
                'followup' => $managed ? $this->followupData($followups->get($thread->id)) : null,
                'deal' => $outcome ? $this->outcomeData($outcome, $actor) : null,
            ];
        });
        return response()->json(['data'=>$data->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),
            'customer_stage_classification_v2'=>true]]);
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
            $row=BrokerCustomerFollowup::query()->lockForUpdate()->firstOrCreate(['user_id'=>$actor->id,'message_thread_id'=>$thread->id]);
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
        $v=$request->validate(['stage'=>['required',Rule::in(self::EDITABLE_CUSTOMER_STAGES)]]);
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
        $v=$request->validate(['page'=>['nullable','integer','min:1'],
            'per_page'=>['nullable','integer','min:1','max:250'],'only_due'=>['nullable','boolean']]);
        $query=$this->availability->updateCandidates($actor, $request->boolean('only_due'));
        // Keep the legacy first-page size; explicit clients can traverse every owned row.
        $page=$query->orderBy('availability_due_at')->orderBy('id')->paginate((int)($v['per_page'] ?? 250));
        return response()->json(['data'=>collect($page->items())->map(fn ($p) => [
            'id'=>$p->id,'title'=>$p->title,'purpose'=>$p->purpose,'availability_status'=>$p->availability_status,
            'confirmed_at'=>$p->availability_confirmed_at?->toIso8601String(),'due_at'=>$p->availability_due_at?->toIso8601String(),
            'notified_at'=>$p->availability_notified_at?->toIso8601String(),'needs_confirmation'=>$p->availability_due_at?->lte(now()) ?? false,
        ])->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),
            'per_page'=>$page->perPage(),'total'=>$page->total()]]);
    }

    public function changeAvailability(Request $request): JsonResponse
    {
        $v=$request->validate(['property_ids'=>['required','array','min:1','max:100'],'property_ids.*'=>['required','integer','distinct','min:1'],
            'state'=>['required',Rule::in(['available','sold','rented'])]]);
        $actor = $this->advertiser($request);
        $rows = DB::transaction(function () use ($actor, $v, $request): array {
            $rows = $this->availability->change($actor, $v['property_ids'], $v['state'], $request);
            if ($v['state'] !== 'available') {
                $externalClosure = app(\App\Services\ExternalListingClosureService::class);
                foreach ($rows as $property) {
                    $externalClosure->record($actor, $property, $request);
                }
            }
            return $rows;
        });
        return response()->json(['data'=>['updated'=>count($rows),'property_ids'=>array_map(fn ($p) => $p->id,$rows),'state'=>$v['state']]]);
    }

    public function reportDeal(Request $request, MessageThread $thread): JsonResponse
    {
        $v=$request->validate(['basis_amount'=>['nullable','numeric','gt:0','max:9999999999999']]);
        $outcome=$this->deals->report($this->advertiser($request),$thread,isset($v['basis_amount']) ? (float)$v['basis_amount'] : null,$request);
        $status = $this->platformDuesForDeals((int) $request->user()->id, [$outcome->id])[$outcome->id] ?? null;
        return response()->json(['data'=>$this->outcomeData($outcome,$request->user(),$status)],201);
    }

    public function activity(Request $request): JsonResponse
    {
        $actor=$request->user();
        $v=$request->validate(['thread_id'=>['nullable','integer','min:1'],'page'=>['nullable','integer','min:1']]);
        $page=BrokerDealOutcome::query()->where(fn ($q) => $q->where('advertiser_user_id',$actor->id)->orWhere('customer_user_id',$actor->id))
            ->when(isset($v['thread_id']),fn ($q) => $q->where('message_thread_id',$v['thread_id']))->latest('id')->paginate(30);
        $rows = collect($page->items());
        $statuses = $this->platformDuesForDeals((int) $actor->id, $rows->pluck('id')->all());
        return response()->json(['data'=>$rows->map(fn ($outcome) =>
            $this->outcomeData($outcome, $actor, $statuses[$outcome->id] ?? null))->values(),
            'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage()]]);
    }

    public function deal(Request $request, BrokerDealOutcome $outcome): JsonResponse
    {
        $actor=$request->user();
        abort_unless(in_array((int)$actor->id,[(int)$outcome->advertiser_user_id,(int)$outcome->customer_user_id],true),404);
        $status = $this->platformDuesForDeals((int) $actor->id, [$outcome->id])[$outcome->id] ?? null;
        return response()->json(['data' => $this->outcomeData($outcome, $actor, $status) + $this->outcomeFinancialData($outcome)]);
    }

    public function viewDeal(Request $request, BrokerDealOutcome $outcome): Response
    {
        $actor = $request->user();
        abort_unless((int) $outcome->advertiser_user_id === (int) $actor->id, 404);
        $v = $request->validate(['revision' => ['required', 'integer', 'between:1,2147483647']]);
        DB::table('broker_deal_outcomes')
            ->where('id', $outcome->id)
            ->where('advertiser_user_id', $actor->id)
            ->where('advertiser_attention_revision', $v['revision'])
            ->where('advertiser_seen_revision', '<', $v['revision'])
            ->update(['advertiser_seen_revision' => $v['revision']]);

        return response()->noContent();
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
        $policy = $this->finance->financialSummaryFor($actor);
        $rows = PropertyPlatformReceivable::query()->where('advertiser_user_id', $actor->id)
            ->outstanding()->with('financialTerm.property')->latest('id')->limit(250)->get();
        $pending = $this->pendingDuesPayments((int) $actor->id, $rows->pluck('deal_financial_term_id')->all());
        // Totals cover every due and confirmed payment. The cards contain only outstanding balances.
        $summary=PropertyPlatformReceivable::query()->where('advertiser_user_id',$actor->id)->groupBy('currency')->select('currency')
            ->selectRaw('SUM(amount_paid) AS paid')
            ->selectRaw("SUM(CASE WHEN status IN ('open','under_review','overdue','disputed') AND amount_total > amount_paid THEN amount_total - amount_paid ELSE 0 END) AS open")
            ->get()->map(fn ($balance) => ['currency'=>$balance->currency,'paid'=>round((float)$balance->paid,2),'open'=>round((float)$balance->open,2)])->values();
        return response()->json(['data'=>['balances'=>$summary,'policy'=>$policy,
            'receivables'=>$rows->map(fn ($r) => ['id'=>$r->id,'reference'=>$r->reference,'property_id'=>$r->property_id,
                'property_title'=>$r->financialTerm?->property?->title,'transaction_type'=>$r->financialTerm?->transaction_type,
                'basis_amount'=>$r->financialTerm?->base_amount,'monthly_basis_amount'=>$r->financialTerm?->monthly_basis_amount,
                'sai_amount'=>$r->financialTerm?->sai_total_amount,
                'amount_total'=>$r->amount_total,'amount_paid'=>$r->amount_paid,'remaining_amount'=>round(max(0,$r->amount_total-$r->amount_paid),2),
                'currency'=>$r->currency,'status'=>$r->status,'due_at'=>$r->due_at?->toIso8601String(),
                'platform_due_status'=>isset($pending[$r->deal_financial_term_id]) || $r->status === 'under_review'
                    ? 'pending_review' : 'pending_payment'])->values()]]);
    }

    private function platformDuesForDeals(int $advertiserId, array $outcomeIds): array
    {
        $rows = PropertyPlatformReceivable::query()->where('property_platform_receivables.advertiser_user_id', $advertiserId)
            ->join('property_deal_financial_terms as terms', 'terms.id', '=', 'property_platform_receivables.deal_financial_term_id')
            ->whereIn('terms.broker_deal_outcome_id', $outcomeIds)
            ->get(['property_platform_receivables.*', 'terms.broker_deal_outcome_id']);
        $pending = $this->pendingDuesPayments($advertiserId, $rows->pluck('deal_financial_term_id')->all());

        return $rows->mapWithKeys(fn (PropertyPlatformReceivable $due): array => [
            $due->broker_deal_outcome_id => match (true) {
                $due->amount_total <= $due->amount_paid => 'paid',
                $due->status === 'under_review' || isset($pending[$due->deal_financial_term_id]) => 'pending_review',
                default => 'pending_payment',
            },
        ])->all();
    }

    private function pendingDuesPayments(int $advertiserId, array $termIds): array
    {
        if ($termIds === []) return [];

        return PropertyPayment::query()->where('payer_user_id', $advertiserId)
            ->where('mode', 'platform_receivable')->whereIn('deal_financial_term_id', $termIds)
            ->whereIn('status', ['proof_submitted', 'under_review'])
            ->distinct()->pluck('deal_financial_term_id')->flip()->all();
    }

    public function recordView(Request $request, Property $property): JsonResponse
    {
        abort_unless($property->isPubliclyAvailable(),404);
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
        $v=$request->validate(['decision'=>['required',Rule::in(['approve','retry','cancel'])],'note'=>['required','string','min:5','max:2000'],'acting_as_agent'=>['nullable','boolean']]);
        $result=$this->deals->resolveSupport($request->user(),$task,$v['decision'],$v['note'],$request,(bool)($v['acting_as_agent'] ?? false));
        return response()->json(['data'=>['id'=>$result->id,'status'=>$result->status]]);
    }

    private function advertiser(Request $request): User
    {
        $actor=$request->user();
        abort_unless($actor && $actor->canManageExistingListings(),403);
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

    private function outcomeData(BrokerDealOutcome $outcome, User $viewer, ?string $platformDueStatus = null): array
    {
        $attentionRevision = (int) $outcome->advertiser_attention_revision;
        $viewRevision = (int) $viewer->id === (int) $outcome->advertiser_user_id
            && $attentionRevision > (int) $outcome->advertiser_seen_revision ? $attentionRevision : null;
        return ['id'=>$outcome->id,'reference'=>$outcome->reference,'property_id'=>$outcome->property_id,
            'advertiser_view_revision'=>$viewRevision,
            'thread_id'=>$outcome->message_thread_id,'advertiser_id'=>$outcome->advertiser_user_id,'customer_id'=>$outcome->customer_user_id,
            'status'=>$outcome->status,'platform_due_status'=>$platformDueStatus,
            'price_confirmation_required'=>$outcome->requiresPriceConfirmation(),
            'transaction_type'=>$outcome->transaction_type,'basis_amount'=>$outcome->basis_amount,'currency'=>$outcome->currency,
            'listing_price'=>$outcome->snapshot['listing_price'] ?? null,'listing_currency'=>$outcome->snapshot['listing_currency'] ?? null,
            'property_title'=>$outcome->snapshot['property_title'],'customer_name'=>$outcome->snapshot['customer_name'],
            'advertiser_name'=>$outcome->snapshot['advertiser_name'],'confirmed_at'=>$outcome->confirmed_at?->toIso8601String(),
            'can_confirm'=>(int)$viewer->id === (int)$outcome->customer_user_id && $outcome->status === 'pending_customer',
            'can_rate'=>(int)$viewer->id === (int)$outcome->customer_user_id && $outcome->status === 'confirmed',
            'can_view_support_case'=>(int)$viewer->id === (int)$outcome->customer_user_id,'support_case_id'=>$outcome->support_case_id];
    }

    private function outcomeFinancialData(BrokerDealOutcome $outcome): array
    {
        $term = PropertyDealFinancialTerm::query()->where('broker_deal_outcome_id', $outcome->id)->first();
        if (! $term) return [];

        $snapshot = $term->snapshot ?? [];
        $rate = $snapshot['sai_rate_percent'] ?? null;
        if (! array_key_exists('sai_rate_percent', $snapshot) && $outcome->sai_term_id) {
            $storedSai = PropertySaiTerm::query()->where('property_id', $outcome->property_id)->find($outcome->sai_term_id);
            if ($storedSai && $storedSai->sai_amount_type !== 'fixed') {
                $rate = $storedSai->sai_rate_percent;
            }
        }

        // An advertiser's platform receivable covers only the platform share.
        // Only a recorded payment that includes the full Sai can say it was paid.
        $paymentStatus = null;
        if ($term->sai_total_amount > 0 && in_array($term->sai_payer, ['buyer', 'tenant'], true)) {
            $paymentStatus = PropertyPayment::query()->where('deal_financial_term_id', $term->id)
                ->where('payer_user_id', $term->buyer_user_id)->where('currency', $term->currency)
                ->whereIn('mode', ['platform_sai_only', 'platform_full'])
                ->orderByRaw("CASE WHEN status = 'confirmed' THEN 0 ELSE 1 END")
                ->latest('id')->value('status');
        }

        return [
            'sai_amount' => $term->sai_total_amount,
            'sai_currency' => $term->currency,
            'sai_rate_percent' => $rate,
            'sai_payment_status' => $paymentStatus,
        ];
    }
}
