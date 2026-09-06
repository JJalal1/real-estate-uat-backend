<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ConversationReport;
use App\Models\MessageThread;
use App\Models\MessageThreadParticipant;
use App\Models\PrivateMessage;
use App\Models\PrivateMessageAccessEvent;
use App\Models\Property;
use App\Models\SupportCase;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\AuditLogService;
use App\Services\SupportCaseService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class MessagingController extends Controller
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly SupportCaseService $support,
        private readonly UserNotificationService $notifications,
    ) {}

    public function threads(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $ids=MessageThreadParticipant::query()->where('user_id',$user->id)->pluck('thread_id');
        $rows=MessageThread::query()->whereIn('id',$ids)->with(['property:id,title,status','participants'])->orderByDesc('last_message_at')->orderByDesc('id')->get();
        return response()->json(['data'=>$rows->map(fn(MessageThread $thread)=>$this->threadSummary($thread,$user))->values()]);
    }

    public function startForProperty(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless($property->status==='published',404);
        if((int)$property->user_id===(int)$user->id) throw ValidationException::withMessages(['property_id'=>['You cannot start a conversation with yourself.']]);
        $owner=User::query()->findOrFail((int)$property->user_id);
        $pair=[(int)$user->id,(int)$owner->id];sort($pair);
        $key='listing:'.$property->id.':'.$pair[0].':'.$pair[1];
        [$thread,$created]=DB::transaction(function()use($property,$user,$owner,$key): array {
            $thread=MessageThread::query()->firstOrCreate(['conversation_key'=>$key],[
                'property_id'=>$property->id,'started_by_user_id'=>$user->id,'last_message_at'=>now(),
            ]);
            $created=$thread->wasRecentlyCreated;
            foreach([[$user->id,$user->name],[$owner->id,$owner->name]] as [$id,$name]){
                MessageThreadParticipant::query()->firstOrCreate(['thread_id'=>$thread->id,'user_id'=>$id],['user_name_snapshot'=>$name]);
            }
            return [$thread->fresh(['property:id,title,status','participants']),$created];
        });
        $this->audit->record($user,'messages.thread_opened',$thread,['property_id'=>$property->id],$request,$owner->id);
        return response()->json(['message'=>'Conversation ready.','data'=>$this->threadSummary($thread,$user)],$created?201:200);
    }

    public function show(Request $request, MessageThread $thread): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $participant=$this->participant($thread,$user);
        $thread->load(['property:id,title,status','participants']);
        $messages=PrivateMessage::query()->where('thread_id',$thread->id)->orderBy('id')->limit(500)->get();
        if($messages->isNotEmpty()){
            $participant->forceFill(['last_read_message_id'=>$messages->last()->id,'last_read_at'=>now()])->save();
            UserNotification::query()->where('user_id',$user->id)->where('entity_type','message_thread')->where('entity_id',$thread->id)->whereNull('read_at')->update(['read_at'=>now()]);
        }
        return response()->json(['data'=>[
            'thread'=>$this->threadSummary($thread,$user),
            'messages'=>$messages->map(fn(PrivateMessage $m)=>$this->messageData($m,$user))->values(),
        ]]);
    }

    public function send(Request $request, MessageThread $thread): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $this->participant($thread,$user);
        $validated=$request->validate(['body'=>['required','string','min:1','max:2000']]);
        $message=DB::transaction(function()use($thread,$user,$validated): PrivateMessage {
            $message=PrivateMessage::query()->create([
                'thread_id'=>$thread->id,'sender_user_id'=>$user->id,'sender_name_snapshot'=>$user->name,
                'body'=>trim($validated['body']),'created_at'=>now(),
            ]);
            $thread->forceFill(['last_message_at'=>now()])->save();
            return $message;
        });
        $recipients=MessageThreadParticipant::query()->where('thread_id',$thread->id)->where('user_id','<>',$user->id)->pluck('user_id');
        foreach($recipients as $recipientId){
            $this->notifications->create((int)$recipientId,'message_received','رسالة جديدة من '.$user->name,'لديك رسالة جديدة داخل التطبيق.','message_thread',$thread->id,['thread_id'=>$thread->id]);
        }
        $this->audit->record($user,'messages.message_sent',$thread,['message_id'=>$message->id,'recipient_count'=>$recipients->count()],$request);
        return response()->json(['message'=>'Message sent.','data'=>$this->messageData($message,$user)],201);
    }

    public function markRead(Request $request, MessageThread $thread): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $participant=$this->participant($thread,$user);
        $latest=(int)(PrivateMessage::query()->where('thread_id',$thread->id)->max('id')??0);
        $participant->forceFill(['last_read_message_id'=>$latest?:null,'last_read_at'=>now()])->save();
        UserNotification::query()->where('user_id',$user->id)->where('entity_type','message_thread')->where('entity_id',$thread->id)->whereNull('read_at')->update(['read_at'=>now()]);
        return response()->json(['message'=>'Conversation marked read.']);
    }

    public function report(Request $request, MessageThread $thread): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $this->participant($thread,$user);
        $validated=$request->validate([
            'reason'=>['required',Rule::in(['abuse','fraud','privacy','harassment','spam','other'])],
            'details'=>['required','string','min:5','max:5000'],
        ]);
        $duplicate=ConversationReport::query()->where('thread_id',$thread->id)->where('reporter_user_id',$user->id)->whereIn('status',['open','under_review'])->exists();
        if($duplicate) throw new ConflictHttpException('An active complaint for this conversation already exists.');
        $case=$this->support->create($user,'report','Conversation complaint',trim($validated['details']),'conversation_thread',$thread->id,$validated['reason'],in_array($validated['reason'],['abuse','fraud','privacy'],true)?'high':'normal',$request);
        $report=ConversationReport::query()->create([
            'thread_id'=>$thread->id,'support_case_id'=>$case->id,'reporter_user_id'=>$user->id,'reporter_name_snapshot'=>$user->name,
            'reason_code'=>$validated['reason'],'details'=>trim($validated['details']),'status'=>'open',
        ]);
        $this->audit->record($user,'messages.conversation_reported',$report,['thread_id'=>$thread->id,'support_case_id'=>$case->id,'reason'=>$validated['reason']],$request);
        return response()->json(['message'=>'Conversation complaint submitted.','data'=>$this->reportSummary($report)],201);
    }

    public function adminReports(Request $request): JsonResponse
    {
        $validated=$request->validate(['status'=>['nullable',Rule::in(['open','under_review','resolved','dismissed'])]]);
        $rows=ConversationReport::query()->with('thread.property:id,title,status')->when($validated['status']??null,fn($q,$v)=>$q->where('status',$v))->latest('id')->limit(200)->get();
        return response()->json(['data'=>$rows->map(fn(ConversationReport $r)=>$this->reportSummary($r))->values()]);
    }

    public function adminOpenReportedContent(Request $request, ConversationReport $report): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_unless(in_array($report->status,['open','under_review'],true),409,'Only active complaints can authorize private conversation access.');
        $thread=MessageThread::query()->with(['property:id,title,status','participants'])->findOrFail($report->thread_id);
        if($report->status==='open') $report->forceFill(['status'=>'under_review'])->save();
        PrivateMessageAccessEvent::query()->create([
            'conversation_report_id'=>$report->id,'thread_id'=>$thread->id,'actor_user_id'=>$actor->id,'actor_name_snapshot'=>$actor->name,
            'action'=>'opened_reported_private_content','created_at'=>now(),
        ]);
        $this->audit->record($actor,'conversations.private_content_opened',$report,[
            'thread_id'=>$thread->id,'support_case_id'=>$report->support_case_id,'workflow'=>'conversation_complaint',
        ],$request,$report->reporter_user_id);
        $messages=PrivateMessage::query()->where('thread_id',$thread->id)->orderBy('id')->limit(500)->get();
        return response()->json(['data'=>[
            'report'=>$this->reportSummary($report->fresh()),
            'thread'=>['id'=>$thread->id,'property_id'=>$thread->property_id,'property_title'=>$thread->property?->title,'participants'=>$thread->participants->map(fn($p)=>['user_id'=>$p->user_id,'name'=>$p->user_name_snapshot])->values()],
            'messages'=>$messages->map(fn(PrivateMessage $m)=>['id'=>$m->id,'sender_user_id'=>$m->sender_user_id,'sender_name'=>$m->sender_name_snapshot,'body'=>$m->body,'created_at'=>$m->created_at?->toIso8601String()])->values(),
        ]]);
    }

    public function adminResolveReport(Request $request, ConversationReport $report): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['status'=>['required',Rule::in(['resolved','dismissed'])],'resolution_note'=>['required','string','min:3','max:1000']]);
        if(!in_array($report->status,['open','under_review'],true)) throw new ConflictHttpException('Conversation complaint is already closed.');
        $report->forceFill([
            'status'=>$validated['status'],'resolved_by_user_id'=>$actor->id,'resolved_by_name_snapshot'=>$actor->name,
            'resolution_note'=>trim($validated['resolution_note']),'resolved_at'=>now(),
        ])->save();
        if($report->support_case_id){
            $case=SupportCase::query()->find($report->support_case_id);
            if($case && !in_array($case->status,SupportCaseService::CLOSED_STATUSES,true)) $this->support->setStatus($actor,$case,$validated['status'],$request);
        }
        $this->notifications->create(
            (int) $report->reporter_user_id,
            'conversation_report_closed',
            'تم تحديث بلاغ المحادثة',
            'تم إغلاق بلاغ المحادثة داخل مركز الدعم.',
            $report->support_case_id ? 'support_case' : 'message_thread',
            (int) ($report->support_case_id ?: $report->thread_id),
            ['status' => $validated['status'], 'report_id' => $report->id],
        );
        $this->audit->record($actor,'messages.conversation_report_closed',$report,['status'=>$validated['status'],'thread_id'=>$report->thread_id],$request,$report->reporter_user_id);
        return response()->json(['message'=>'Conversation complaint closed.','data'=>$this->reportSummary($report)]);
    }

    private function participant(MessageThread $thread, User $user): MessageThreadParticipant
    {
        $participant=MessageThreadParticipant::query()->where('thread_id',$thread->id)->where('user_id',$user->id)->first();
        abort_unless($participant,404);return $participant;
    }

    private function threadSummary(MessageThread $thread, User $user): array
    {
        if(!$thread->relationLoaded('participants')) $thread->load('participants');
        $me=$thread->participants->firstWhere('user_id',$user->id);
        $other=$thread->participants->first(fn($p)=>(int)$p->user_id!==(int)$user->id);
        $latest=PrivateMessage::query()->where('thread_id',$thread->id)->latest('id')->first();
        $unread=PrivateMessage::query()->where('thread_id',$thread->id)->where('sender_user_id','<>',$user->id)->when($me?->last_read_message_id,fn($q,$id)=>$q->where('id','>',$id))->count();
        return [
            'id'=>$thread->id,'property_id'=>$thread->property_id,'property_title'=>$thread->property?->title,
            'other_user'=>['id'=>$other?->user_id,'name'=>$other?->user_name_snapshot ?? 'مستخدم'],
            'unread_count'=>$unread,'last_message_preview'=>$latest?->body ? mb_substr($latest->body,0,120) : null,
            'last_message_at'=>$thread->last_message_at?->toIso8601String(),'created_at'=>$thread->created_at?->toIso8601String(),
        ];
    }

    private function messageData(PrivateMessage $message, User $viewer): array
    {
        return ['id'=>$message->id,'sender_user_id'=>$message->sender_user_id,'sender_name'=>$message->sender_name_snapshot,'body'=>$message->body,'is_mine'=>(int)$message->sender_user_id===(int)$viewer->id,'created_at'=>$message->created_at?->toIso8601String()];
    }

    private function reportSummary(ConversationReport $report): array
    {
        if(!$report->relationLoaded('thread')) $report->load('thread.property:id,title,status');
        return [
            'id'=>$report->id,'thread_id'=>$report->thread_id,'support_case_id'=>$report->support_case_id,
            'property_id'=>$report->thread?->property_id,'property_title'=>$report->thread?->property?->title,
            'reporter_user_id'=>$report->reporter_user_id,'reporter_name'=>$report->reporter_name_snapshot,
            'reason_code'=>$report->reason_code,'status'=>$report->status,'resolved_by_name'=>$report->resolved_by_name_snapshot,
            'resolved_at'=>$report->resolved_at?->toIso8601String(),'created_at'=>$report->created_at?->toIso8601String(),
        ];
    }
}
