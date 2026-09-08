<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DevelopmentUnit;
use App\Models\MessageThread;
use App\Models\MessageThreadParticipant;
use App\Models\PrivateMessage;
use App\Models\Property;
use App\Models\User;
use App\Models\ViewingBooking;
use App\Models\ViewingBookingEvent;
use App\Services\AuditLogService;
use App\Services\UserNotificationService;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class BookingController extends Controller
{
    public function __construct(private readonly AuditLogService $audit,private readonly UserNotificationService $notifications) {}

    public function mine(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=ViewingBooking::query()->where(fn(Builder $q)=>$q->where('requester_user_id',$user->id)->orWhere('host_user_id',$user->id))->orderByDesc('starts_at')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(ViewingBooking $b)=>$this->bookingData($b,$user))->values()]);
    }

    public function managed(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$global=$user->hasPermission('bookings.manage');$development=$user->hasPermission('developments.manage');abort_unless($global||$development,403);
        $q=ViewingBooking::query();if(!$global)$q->where('target_type','development_unit');
        $rows=$q->orderByDesc('starts_at')->limit(300)->get();return response()->json(['data'=>$rows->map(fn(ViewingBooking $b)=>$this->bookingData($b,$user))->values()]);
    }

    public function show(Request $request, ViewingBooking $booking): JsonResponse
    {
        /** @var User $user */ $user=$request->user();abort_unless($this->canView($user,$booking),404);$booking->load('events');return response()->json(['data'=>$this->bookingData($booking,$user,true)]);
    }

    public function requestForProperty(Request $request, Property $property): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();abort_unless($property->status==='published',404);abort_if((int)$property->user_id===(int)$actor->id,409,'You cannot request a viewing for your own listing.');
        $host=User::query()->find($property->user_id);abort_if(!$host||!$host->isActive(),409,'The advertiser is unavailable for viewings.');$schedule=$this->schedule($request);
        return $this->createBooking($request,$actor,['type'=>'property','id'=>$property->id,'title'=>$property->title,'address'=>$property->address,'host'=>$host],$schedule);
    }

    public function requestForUnit(Request $request, DevelopmentUnit $unit): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$unit->load('development.developer');$development=$unit->development;
        abort_unless($development&&$development->status==='published'&&$development->developer?->status==='active'&&$unit->status==='available',404);
        $host=null;if($development->created_by_user_id){$candidate=User::query()->find($development->created_by_user_id);if($candidate?->isActive())$host=$candidate;}
        return $this->createBooking($request,$actor,['type'=>'development_unit','id'=>$unit->id,'title'=>$development->name.' - '.$unit->title.' ('.$unit->code.')','address'=>$development->address,'host'=>$host],$this->schedule($request));
    }

    public function confirm(Request $request, ViewingBooking $booking): JsonResponse
    {
        $validated=$request->validate(['note'=>['nullable','string','max:2000']]);/** @var User $actor */ $actor=$request->user();
        $result=DB::transaction(function()use($booking,$actor,$validated,$request){
            $b=ViewingBooking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();abort_unless($b->status==='requested',409,'Only requested bookings can be confirmed.');
            $awaitingRequester=$this->awaitsRequesterAcceptance($b);$actorIsRequester=(int)$b->requester_user_id===(int)$actor->id;
            if($awaitingRequester){abort_unless($actorIsRequester,409,'The requester must accept the host reschedule.');}
            else{abort_unless($this->canManage($actor,$b),403);}
            $host=$this->currentHostForConfirmation($actor,$b);$hostId=$host?->id;$this->acquireScheduleLocks($b,$hostId);$this->assertNoConfirmedConflict($b,$b->starts_at,$b->ends_at,$hostId);
            $event=$awaitingRequester?'reschedule_accepted':'confirmed';$audit=$awaitingRequester?'booking.reschedule_accepted':'booking.confirmed';
            $b->forceFill(['status'=>'confirmed','host_user_id'=>$hostId,'host_name_snapshot'=>$host?->name,'host_note'=>$awaitingRequester?$b->host_note:($validated['note']??$b->host_note),'confirmed_at'=>now(),'declined_at'=>null,'cancelled_at'=>null,'cancellation_reason'=>null,'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name])->save();
            $this->event($b,$actor,$event,'requested','confirmed',['starts_at'=>$b->starts_at?->toIso8601String(),'ends_at'=>$b->ends_at?->toIso8601String()]);$this->audit->record($actor,$audit,$b,[],$request,$awaitingRequester?$hostId:$b->requester_user_id);
            if($awaitingRequester){if($hostId)$this->notify((int)$hostId,'booking_reschedule_accepted','تم قبول الموعد الجديد','وافق طالب المعاينة على الموعد الجديد لـ '.$b->target_title_snapshot.'.',$b);}else{$this->notify($b->requester_user_id,'booking_confirmed','تم تأكيد موعد المعاينة','تم تأكيد موعد معاينة '.$b->target_title_snapshot.'.',$b);}
            return $b->fresh();
        });
        return response()->json(['message'=>'Viewing booking confirmed.','data'=>$this->bookingData($result,$actor)]);
    }

    public function decline(Request $request, ViewingBooking $booking): JsonResponse
    {
        $validated=$request->validate(['note'=>['required','string','min:2','max:2000']]);/** @var User $actor */ $actor=$request->user();
        $result=DB::transaction(function()use($booking,$actor,$validated,$request){$b=ViewingBooking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();abort_unless($this->canManage($actor,$b),403);abort_unless($b->status==='requested',409,'Only requested bookings can be declined.');$from=$b->status;$b->forceFill(['status'=>'declined','host_note'=>$validated['note'],'declined_at'=>now(),'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name])->save();$this->event($b,$actor,'declined',$from,'declined');$this->audit->record($actor,'booking.declined',$b,[],$request,$b->requester_user_id);$this->notify($b->requester_user_id,'booking_declined','تعذر تأكيد موعد المعاينة','تم رفض طلب معاينة '.$b->target_title_snapshot.'.',$b);return $b->fresh();});
        return response()->json(['message'=>'Viewing booking declined.','data'=>$this->bookingData($result,$actor)]);
    }

    public function cancel(Request $request, ViewingBooking $booking): JsonResponse
    {
        $validated=$request->validate(['reason'=>['required','string','min:2','max:1500']]);/** @var User $actor */ $actor=$request->user();
        $result=DB::transaction(function()use($booking,$actor,$validated,$request){$b=ViewingBooking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();abort_unless($this->canCancel($actor,$b),403);abort_unless(in_array($b->status,['requested','confirmed'],true),409,'This booking can no longer be cancelled.');$from=$b->status;$byRequester=(int)$b->requester_user_id===(int)$actor->id;$b->forceFill(['status'=>'cancelled','cancellation_reason'=>$validated['reason'],'cancelled_at'=>now(),'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name])->save();$this->event($b,$actor,$byRequester?'cancelled_by_requester':'cancelled_by_host',$from,'cancelled');$this->audit->record($actor,'booking.cancelled',$b,['cancelled_by'=>$byRequester?'requester':'host_or_manager'],$request,$byRequester?$b->host_user_id:$b->requester_user_id);$other=$byRequester?$b->host_user_id:$b->requester_user_id;if($other)$this->notify((int)$other,'booking_cancelled','تم إلغاء موعد المعاينة','تم إلغاء موعد معاينة '.$b->target_title_snapshot.'.',$b);return $b->fresh();});
        return response()->json(['message'=>'Viewing booking cancelled.','data'=>$this->bookingData($result,$actor)]);
    }

    public function reschedule(Request $request, ViewingBooking $booking): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$schedule=$this->schedule($request);$validated=$request->validate(['note'=>['nullable','string','max:2000']]);
        $result=DB::transaction(function()use($booking,$actor,$schedule,$validated,$request){$b=ViewingBooking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();abort_unless($this->canCancel($actor,$b),403);abort_unless(in_array($b->status,['requested','confirmed'],true),409,'This booking can no longer be rescheduled.');$hostId=$b->host_user_id;$this->acquireScheduleLocks($b,$hostId);$this->assertNoConfirmedConflict($b,$schedule['start'],$schedule['end'],$hostId);$this->assertNoDuplicateActive($b->requester_user_id,$b->target_type,$b->target_id,$schedule['start'],$schedule['end'],$b->id);$from=$b->status;$byRequester=(int)$b->requester_user_id===(int)$actor->id;$changes=['starts_at'=>$schedule['start'],'ends_at'=>$schedule['end'],'timezone'=>$schedule['timezone'],'status'=>'requested','confirmed_at'=>null,'declined_at'=>null,'cancelled_at'=>null,'cancellation_reason'=>null,'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name];if($byRequester){$changes['requester_note']=$validated['note']??$b->requester_note;$changes['host_note']=null;}else{$changes['host_note']=$validated['note']??$b->host_note;}$b->forceFill($changes)->save();$this->event($b,$actor,'rescheduled',$from,'requested',['starts_at'=>$b->starts_at?->toIso8601String(),'ends_at'=>$b->ends_at?->toIso8601String(),'proposed_by'=>$byRequester?'requester':'host']);$this->audit->record($actor,'booking.rescheduled',$b,['proposed_by'=>$byRequester?'requester':'host_or_manager'],$request);$other=$byRequester?$b->host_user_id:$b->requester_user_id;if($other)$this->notify((int)$other,'booking_rescheduled','تم اقتراح موعد معاينة جديد',$byRequester?'اقترح طالب المعاينة موعداً جديداً لـ '.$b->target_title_snapshot.' ويحتاج إلى تأكيد المعلن.':'اقترح المعلن موعداً جديداً لـ '.$b->target_title_snapshot.' ويحتاج إلى موافقتك.',$b);return $b->fresh();});
        return response()->json(['message'=>'Viewing booking rescheduled and returned to requested status.','data'=>$this->bookingData($result,$actor)]);
    }

    public function complete(Request $request, ViewingBooking $booking): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$result=DB::transaction(function()use($booking,$actor,$request){$b=ViewingBooking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();abort_unless($this->canManage($actor,$b),403);abort_unless($b->status==='confirmed',409,'Only confirmed bookings can be completed.');abort_if(now()->lt($b->ends_at),409,'The viewing cannot be completed before its scheduled end time.');$b->forceFill(['status'=>'completed','completed_at'=>now(),'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name])->save();$this->event($b,$actor,'completed','confirmed','completed');$this->audit->record($actor,'booking.completed',$b,[],$request,$b->requester_user_id);$this->notify($b->requester_user_id,'booking_completed','اكتملت المعاينة','تم تسجيل معاينة '.$b->target_title_snapshot.' كمكتملة.',$b);return $b->fresh();});return response()->json(['message'=>'Viewing booking completed.','data'=>$this->bookingData($result,$actor)]);
    }

    private function createBooking(Request $request, User $actor, array $target, array $schedule): JsonResponse
    {
        $validated=$request->validate(['note'=>['nullable','string','max:2000']]);$booking=DB::transaction(function()use($actor,$target,$schedule,$validated): ViewingBooking{$this->acquireRequestLocks($actor->id,$target['type'],(int)$target['id']);$this->assertNoDuplicateActive($actor->id,$target['type'],$target['id'],$schedule['start'],$schedule['end']);$thread=null;if($target['type']==='property'&&$target['host'] instanceof User)$thread=$this->ensurePropertyConversation($actor,$target['host'],(int)$target['id']);$booking=ViewingBooking::query()->create(['reference'=>$this->reference(),'requester_user_id'=>$actor->id,'requester_name_snapshot'=>$actor->name,'host_user_id'=>$target['host']?->id,'host_name_snapshot'=>$target['host']?->name,'message_thread_id'=>$thread?->id,'target_type'=>$target['type'],'target_id'=>$target['id'],'target_title_snapshot'=>$target['title'],'target_address_snapshot'=>$target['address'],'starts_at'=>$schedule['start'],'ends_at'=>$schedule['end'],'timezone'=>$schedule['timezone'],'status'=>'requested','requester_note'=>$validated['note']??null,'last_action_by_user_id'=>$actor->id,'last_action_by_name_snapshot'=>$actor->name]);if($thread){PrivateMessage::query()->create(['thread_id'=>$thread->id,'sender_user_id'=>$actor->id,'sender_name_snapshot'=>$actor->name,'body'=>$this->viewingConversationMessage($booking),'created_at'=>now()]);$thread->forceFill(['last_message_at'=>now()])->save();}return $booking;});$this->event($booking,$actor,'requested',null,'requested',['starts_at'=>$booking->starts_at?->toIso8601String(),'ends_at'=>$booking->ends_at?->toIso8601String(),'message_thread_id'=>$booking->message_thread_id]);$this->audit->record($actor,'booking.requested',$booking,['target_type'=>$booking->target_type,'target_id'=>$booking->target_id,'message_thread_id'=>$booking->message_thread_id],$request,$booking->host_user_id);if($booking->host_user_id)$this->notify((int)$booking->host_user_id,'viewing_requested','طلب معاينة جديد','لديك طلب معاينة جديد لـ '.$booking->target_title_snapshot.'. افتح المحادثة للتنسيق وتأكيد الموعد.',$booking);return response()->json(['message'=>'Viewing booking requested.','data'=>$this->bookingData($booking,$actor)],201);
    }

    private function ensurePropertyConversation(User $requester,User $host,int $propertyId): MessageThread
    {
        $pair=[(int)$requester->id,(int)$host->id];sort($pair);$key='listing:'.$propertyId.':'.$pair[0].':'.$pair[1];$thread=MessageThread::query()->firstOrCreate(['conversation_key'=>$key],['property_id'=>$propertyId,'started_by_user_id'=>$requester->id,'last_message_at'=>now()]);foreach([[$requester->id,$requester->name],[$host->id,$host->name]] as [$id,$name])MessageThreadParticipant::query()->firstOrCreate(['thread_id'=>$thread->id,'user_id'=>$id],['user_name_snapshot'=>$name]);return $thread;
    }

    private function viewingConversationMessage(ViewingBooking $booking): string
    {
        $message='طلب معاينة جديد للعقار «'.$booking->target_title_snapshot.'». يمكننا التنسيق هنا، وبعد الاتفاق يستطيع المعلن تأكيد الموعد من بطاقة المعاينة.';if(trim((string)$booking->requester_note)!=='')$message.="\nملاحظة الطلب: ".trim((string)$booking->requester_note);return $message;
    }

    private function schedule(Request $request): array
    {
        $v=$request->validate(['starts_at'=>['required','date'],'ends_at'=>['required','date','after:starts_at'],'timezone'=>['nullable','string','max:64']]);$start=CarbonImmutable::parse((string)$v['starts_at']);$end=CarbonImmutable::parse((string)$v['ends_at']);if($start->lt(now()->addMinutes(30)))throw ValidationException::withMessages(['starts_at'=>['Viewing requests must start at least 30 minutes in the future.']]);if($start->gt(now()->addDays(120)))throw ValidationException::withMessages(['starts_at'=>['Viewing requests cannot be more than 120 days ahead.']]);$minutes=$start->diffInMinutes($end);if($minutes<30||$minutes>240)throw ValidationException::withMessages(['ends_at'=>['Viewing duration must be between 30 minutes and 4 hours.']]);return ['start'=>$start,'end'=>$end,'timezone'=>trim((string)($v['timezone']??'UTC'))?:'UTC'];
    }

    private function currentHostForConfirmation(User $actor,ViewingBooking $booking): ?User
    {
        if($booking->target_type==='property'){$property=Property::query()->whereKey($booking->target_id)->where('status','published')->first();abort_if(!$property,409,'The listing is no longer published.');$host=User::query()->find($property->user_id);abort_if(!$host||!$host->isActive(),409,'The advertiser is unavailable.');return $host;}
        $unit=DevelopmentUnit::query()->with('development.developer')->find($booking->target_id);$development=$unit?->development;abort_if(!$unit||!$development||$development->status!=='published'||$development->developer?->status!=='active'||$unit->status!=='available',409,'The development unit is no longer available for viewing.');if($booking->host_user_id){$host=User::query()->find($booking->host_user_id);if($host?->isActive())return $host;}return $this->canManage($actor,$booking)?$actor:null;
    }

    private function assertNoDuplicateActive(int $requesterId,string $type,int $targetId,CarbonImmutable $start,CarbonImmutable $end,?int $exclude=null): void
    {
        $q=ViewingBooking::query()->where('requester_user_id',$requesterId)->where('target_type',$type)->where('target_id',$targetId)->whereIn('status',['requested','confirmed'])->where('starts_at','<',$end)->where('ends_at','>',$start);if($exclude)$q->where('id','<>',$exclude);abort_if($q->exists(),409,'You already have an overlapping active request for this target.');
    }

    private function assertNoConfirmedConflict(ViewingBooking $booking,$start,$end,?int $hostId): void
    {
        $base=fn()=>ViewingBooking::query()->where('status','confirmed')->where('id','<>',$booking->id)->where('starts_at','<',$end)->where('ends_at','>',$start);abort_if($base()->where('target_type',$booking->target_type)->where('target_id',$booking->target_id)->exists(),409,'The target already has a confirmed viewing in this time window.');abort_if($base()->where('requester_user_id',$booking->requester_user_id)->exists(),409,'The requester already has another confirmed viewing in this time window.');if($hostId)abort_if($base()->where('host_user_id',$hostId)->exists(),409,'The host already has another confirmed viewing in this time window.');
    }

    private function acquireRequestLocks(int $requesterId,string $type,int $targetId): void
    {
        if(DB::connection()->getDriverName()!=='pgsql')return;$keys=['booking-requester:'.$requesterId,'booking-target:'.$type.':'.$targetId];sort($keys);foreach($keys as $key)DB::select('SELECT pg_advisory_xact_lock(hashtext(?))',[$key]);
    }

    private function acquireScheduleLocks(ViewingBooking $booking,?int $hostId): void
    {
        if(DB::connection()->getDriverName()!=='pgsql')return;$keys=['booking-target:'.$booking->target_type.':'.$booking->target_id,'booking-user:'.$booking->requester_user_id];if($hostId)$keys[]='booking-host:'.$hostId;sort($keys);foreach($keys as $key)DB::select('SELECT pg_advisory_xact_lock(hashtext(?))',[$key]);
    }

    private function awaitsRequesterAcceptance(ViewingBooking $booking): bool
    {
        return $booking->status==='requested'&&$booking->last_action_by_user_id&&(int)$booking->last_action_by_user_id!==(int)$booking->requester_user_id;
    }

    private function canView(User $user,ViewingBooking $booking): bool {return (int)$booking->requester_user_id===(int)$user->id||(int)($booking->host_user_id??0)===(int)$user->id||$this->canManage($user,$booking);}
    private function canManage(User $user,ViewingBooking $booking): bool {if($user->hasPermission('bookings.manage'))return true;if((int)($booking->host_user_id??0)===(int)$user->id)return true;return $booking->target_type==='development_unit'&&$user->hasPermission('developments.manage');}
    private function canCancel(User $user,ViewingBooking $booking): bool {return (int)$booking->requester_user_id===(int)$user->id||$this->canManage($user,$booking);}
    private function event(ViewingBooking $booking,?User $actor,string $event,?string $from,?string $to,array $metadata=[]): void {ViewingBookingEvent::query()->create(['viewing_booking_id'=>$booking->id,'actor_user_id'=>$actor?->id,'actor_name_snapshot'=>$actor?->name,'event'=>$event,'from_status'=>$from,'to_status'=>$to,'metadata'=>$metadata?:null,'created_at'=>now()]);}

    private function notify(int $userId,string $type,string $title,string $body,ViewingBooking $booking): void
    {
        $threadId=$booking->message_thread_id?(int)$booking->message_thread_id:null;$this->notifications->create($userId,$type,$title,$body,$threadId?'message_thread':'viewing_booking',$threadId?:$booking->id,['booking_id'=>$booking->id,'reference'=>$booking->reference,'status'=>$booking->status,'message_thread_id'=>$threadId]);
    }

    private function reference(): string {for($i=0;$i<8;$i++){$reference='V'.strtoupper(bin2hex(random_bytes(6)));if(!ViewingBooking::query()->where('reference',$reference)->exists())return $reference;}throw new \RuntimeException('Could not allocate viewing booking reference.');}

    private function bookingData(ViewingBooking $b,User $viewer,bool $includeEvents=false): array
    {
        $isRequester=(int)$b->requester_user_id===(int)$viewer->id;$awaitingRequester=$this->awaitsRequesterAcceptance($b);$canManage=$this->canManage($viewer,$b);$data=['id'=>$b->id,'reference'=>$b->reference,'requester_user_id'=>$b->requester_user_id,'requester_name'=>$b->requester_name_snapshot,'host_user_id'=>$b->host_user_id,'host_name'=>$b->host_name_snapshot,'message_thread_id'=>$b->message_thread_id,'target_type'=>$b->target_type,'target_id'=>$b->target_id,'target_title'=>$b->target_title_snapshot,'target_address'=>$b->target_address_snapshot,'starts_at'=>$b->starts_at?->toIso8601String(),'ends_at'=>$b->ends_at?->toIso8601String(),'timezone'=>$b->timezone,'status'=>$b->status,'requester_note'=>$b->requester_note,'host_note'=>$b->host_note,'cancellation_reason'=>$b->cancellation_reason,'confirmed_at'=>$b->confirmed_at?->toIso8601String(),'cancelled_at'=>$b->cancelled_at?->toIso8601String(),'completed_at'=>$b->completed_at?->toIso8601String(),'last_action_by_user_id'=>$b->last_action_by_user_id,'last_action_by_name'=>$b->last_action_by_name_snapshot,'is_requester'=>$isRequester,'awaiting_requester_confirmation'=>$awaitingRequester,'can_manage'=>$canManage,'can_confirm'=>($canManage&&$b->status==='requested'&&!$awaitingRequester)||($isRequester&&$awaitingRequester),'can_decline'=>$canManage&&$b->status==='requested','can_accept_reschedule'=>$isRequester&&$awaitingRequester,'can_cancel'=>$this->canCancel($viewer,$b)&&in_array($b->status,['requested','confirmed'],true),'can_reschedule'=>$this->canCancel($viewer,$b)&&in_array($b->status,['requested','confirmed'],true)];if($includeEvents){if(!$b->relationLoaded('events'))$b->load('events');$data['events']=$b->events->map(fn(ViewingBookingEvent $e)=>['id'=>$e->id,'actor_name'=>$e->actor_name_snapshot,'event'=>$e->event,'from_status'=>$e->from_status,'to_status'=>$e->to_status,'metadata'=>$e->metadata,'created_at'=>$e->created_at?->toIso8601String()])->values();}return $data;
    }
}
