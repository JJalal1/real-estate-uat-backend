<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AccessControlService;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AccessControlController extends Controller
{
    public function __construct(
        private readonly AccessControlService $access,
        private readonly AuditLogService $audit,
        private readonly ApiTokenService $tokens,
    ) {}

    public function catalog(Request $request): JsonResponse
    {
        $roles=Role::query()->orderBy('id')->get(['key','name_ar','name_en']);
        $permissions=Permission::query()->orderBy('scope')->orderBy('key')->get(['key','name_ar','name_en','scope']);
        return response()->json(['data'=>['roles'=>$roles,'permissions'=>$permissions]]);
    }

    public function users(Request $request): JsonResponse
    {
        $v=$request->validate(['search'=>['nullable','string','max:120'],'per_page'=>['nullable','integer','min:1','max:50']]);
        $query=User::query()->with(['roles','permissionOverrides.permission','accountVerificationProfile'])->where('email','<>','stage5-owner@local.invalid');
        $search=trim((string)($v['search'] ?? ''));
        if ($search !== '') $query->where(fn($q)=>$q->where('name','like','%'.$search.'%')->orWhere('email','like','%'.$search.'%')->orWhere('phone','like','%'.$search.'%'));
        $page=$query->orderByDesc('is_platform_owner')->orderBy('id')->paginate((int)($v['per_page'] ?? 25));
        return response()->json(['data'=>collect($page->items())->map(fn(User $u)=>$this->userData($u))->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()]]);
    }

    public function updateStatus(Request $request, User $user): JsonResponse
    {
        $v=$request->validate(['account_status'=>['required',Rule::in([User::STATUS_ACTIVE,User::STATUS_PENDING_VERIFICATION,User::STATUS_SUSPENDED,User::STATUS_BANNED])]]);
        $updated=$this->access->changeStatus($request->user(),$user,(string)$v['account_status'],$request,$this->tokens);
        return response()->json(['message'=>'Account status updated.','data'=>['user'=>$this->userData($updated)]]);
    }

    public function updateRoles(Request $request, User $user): JsonResponse
    {
        $v=$request->validate(['role_keys'=>['present','array','max:8'],'role_keys.*'=>['string','max:80','distinct']]);
        $updated=$this->access->replaceRoles($request->user(),$user,$v['role_keys'],$request);
        return response()->json(['message'=>'Roles updated.','data'=>['user'=>$this->userData($updated)]]);
    }

    public function updatePermissionOverrides(Request $request, User $user): JsonResponse
    {
        $v=$request->validate([
            'overrides'=>['required','array','max:50'],
            'overrides.*.permission_key'=>['required','string','max:120','distinct'],
            'overrides.*.effect'=>['required',Rule::in(['allow','deny'])],
            'overrides.*.reason'=>['nullable','string','max:500'],
        ]);
        foreach($v['overrides'] as $item){
            if (! Permission::query()->where('key',$item['permission_key'])->exists()) {
                return response()->json(['message'=>'Unknown permission key: '.$item['permission_key'],'code'=>'VALIDATION_ERROR'],422);
            }
        }
        $updated=$this->access->replaceOverrides($request->user(),$user,$v['overrides'],$request);
        return response()->json(['message'=>'Permission overrides updated.','data'=>['user'=>$this->userData($updated)]]);
    }

    public function auditLogs(Request $request): JsonResponse
    {
        $v=$request->validate([
            'action'=>['nullable','string','max:120'],'action_prefix'=>['nullable','string','max:120'],
            'actor_user_id'=>['nullable','integer','exists:users,id'],'target_user_id'=>['nullable','integer','exists:users,id'],
            'per_page'=>['nullable','integer','min:1','max:100'],
        ]);
        $query=AuditLog::query()->latest('id');
        if (! empty($v['action'])) $query->where('action',(string)$v['action']);
        if (! empty($v['action_prefix'])) $query->where('action','like',(string)$v['action_prefix'].'%');
        if (! empty($v['actor_user_id'])) $query->where('actor_user_id',(int)$v['actor_user_id']);
        if (! empty($v['target_user_id'])) $query->where('target_user_id',(int)$v['target_user_id']);
        $page=$query->paginate((int)($v['per_page'] ?? 50));
        return response()->json(['data'=>collect($page->items())->map(fn(AuditLog $log)=>[
            'id'=>$log->id,'actor_user_id'=>$log->actor_user_id,'actor_name'=>$log->actor_name_snapshot,
            'target_user_id'=>$log->target_user_id,'action'=>$log->action,'subject_type'=>$log->subject_type,
            'subject_id'=>$log->subject_id,'metadata'=>$log->metadata,'created_at'=>$log->created_at?->toIso8601String(),
        ])->values(),'meta'=>['current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'total'=>$page->total()]]);
    }

    private function userData(User $user): array
    {
        $user->loadMissing(['roles','permissionOverrides.permission','accountVerificationProfile']);
        return [
            'id'=>(int)$user->id,'name'=>$user->name,'email'=>$user->email,'phone'=>$user->phone,
            'account_status'=>$user->account_status,'phone_verified_at'=>$user->phone_verified_at?->toIso8601String(),
            'account_type'=>$user->account_type,'broker_verification_status'=>$user->broker_verification_status,
            'verification_type'=>$user->accountVerificationProfile?->type,
            'verification_status'=>$user->accountVerificationProfile?->status ?? 'not_submitted',
            'created_at'=>$user->created_at?->toIso8601String(),
            'is_platform_owner'=>(bool)$user->is_platform_owner,'roles'=>$user->roleKeys(),
            'permissions'=>$user->effectivePermissionKeys(),'permission_overrides'=>$user->permissionOverrides->map(fn($o)=>[
                'permission_key'=>$o->permission->key,'effect'=>$o->effect,'reason'=>$o->reason,
            ])->values()->all(),
        ];
    }
}
