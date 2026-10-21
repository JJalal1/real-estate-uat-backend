<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportCase;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\SupportCaseService;
use App\Services\UserMessagingBlockService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AccountSafetyController extends Controller
{
    public function blocked(Request $request)
    {
        $rows=DB::table('user_messaging_blocks')->join('users','users.id','=','user_messaging_blocks.blocked_user_id')
            ->where('user_messaging_blocks.user_id',$request->user()->id)->orderByDesc('user_messaging_blocks.id')
            ->paginate(30,['users.id','users.name','user_messaging_blocks.created_at']);
        return response()->json(['data'=>$rows->items(),'meta'=>['current_page'=>$rows->currentPage(),'last_page'=>$rows->lastPage()]]);
    }
    public function block(Request $request,User $user,UserMessagingBlockService $blocks,AuditLogService $audit)
    {
        $actor=$request->user();abort_if($actor->id===$user->id,422,'لا يمكنك حظر حسابك.');
        DB::transaction(function()use($actor,$user,$blocks,$audit,$request):void {
            $blocks->lockPair($actor->id,$user->id);
            if (DB::table('user_messaging_blocks')->where('user_id',$actor->id)->where('blocked_user_id',$user->id)->exists()) return;
            DB::table('user_messaging_blocks')->insert(['user_id'=>$actor->id,'blocked_user_id'=>$user->id,'created_at'=>now(),'updated_at'=>now()]);
            $audit->record($actor,'messages.user_blocked',$user,[],$request,$user->id);
        });
        return response()->json(['data'=>['user_id'=>$user->id,'blocked_by_me'=>true],'message'=>'تم الحظر. تبقى المحادثات السابقة محفوظة.']);
    }
    public function unblock(Request $request,User $user,UserMessagingBlockService $blocks,AuditLogService $audit)
    {
        $actor=$request->user();
        DB::transaction(function()use($actor,$user,$blocks,$audit,$request):void {
            $blocks->lockPair($actor->id,$user->id);
            if (DB::table('user_messaging_blocks')->where('user_id',$actor->id)->where('blocked_user_id',$user->id)->delete()) {
                $audit->record($actor,'messages.user_unblocked',$user,[],$request,$user->id);
            }
        });
        return response()->json(['data'=>['user_id'=>$user->id,'blocked_by_me'=>false],'message'=>'أُلغي الحظر الذي وضعته.']);
    }
    public function deletionStatus(Request $request)
    {
        return response()->json(['data'=>$this->deletionData($this->deletionQuery($request->user())->first())]);
    }
    public function requestDeletion(Request $request,SupportCaseService $support)
    {
        $request->validate(['confirmed'=>['required','accepted'],'note'=>['nullable','string','max:1000']]);
        $case=DB::transaction(function()use($request,$support){
            $actor=User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $existing=$this->deletionQuery($actor)->whereIn('status',SupportCaseService::ACTIVE_STATUSES)->first();
            if ($existing) return $existing;
            return $support->create($actor,'support_ticket','طلب حذف الحساب',
                'طلب مراجعة حذف الحساب والبيانات. لا ينفذ حذفًا نهائيًا، ومدد الاحتفاظ والحقوق القائمة تنتظر سياسة معتمدة.'.
                ($request->filled('note')?"\nملاحظة صاحب الحساب: ".trim((string)$request->input('note')):''),
                'account_deletion',$actor->id,'account_deletion','normal',$request);
        });
        return response()->json(['message'=>'وصل طلبك إلى الدعم للمراجعة. لم يُحذف الحساب أو أي بيانات.','data'=>$this->deletionData($case)],200);
    }
    private function deletionQuery(User $actor)
    {
        return SupportCase::query()->where('kind','support_ticket')->where('reason_code','account_deletion')
            ->where('target_type','account_deletion')->where('target_id',$actor->id)->where('requester_user_id',$actor->id)->latest('id');
    }
    private function deletionData(?SupportCase $case):array
    {
        return ['reference'=>$case?->reference,'case_id'=>$case?->id,'status'=>$case?->status ?? 'not_requested',
            'requested_at'=>$case?->created_at?->toIso8601String(),'final_deletion_enabled'=>false,'account_deleted'=>false,
            'message'=>'الطلب للمراجعة فقط. لا حذف نهائي قبل اعتماد سياسة البيانات والحقوق القائمة.'];
    }
}
