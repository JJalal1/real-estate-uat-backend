<?php
namespace App\Services;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Models\UserPermissionOverride;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class AccessControlService
{
    public const ROLE_SUPER_ADMIN='super_admin';
    public const ROLE_REGISTERED_USER='registered_user';

    public function __construct(private readonly AuditLogService $audit) {}

    public function ensureRegisteredUser(User $user, ?User $actor=null): void
    {
        $role=Role::query()->where('key',self::ROLE_REGISTERED_USER)->first();
        if ($role) $user->roles()->syncWithoutDetaching([$role->id=>['assigned_by_user_id'=>$actor?->id,'created_at'=>now()]]);
    }

    public function bootstrapPlatformOwner(User $user): void
    {
        DB::transaction(function () use ($user): void {
            if ($user->email === 'stage5-owner@local.invalid') throw new \RuntimeException('Stage 5 placeholder cannot be platform owner.');
            User::query()->where('is_platform_owner',true)->where('id','<>',$user->id)->update(['is_platform_owner'=>false]);
            $user->forceFill(['is_platform_owner'=>true])->save();
            $role=Role::query()->where('key',self::ROLE_SUPER_ADMIN)->firstOrFail();
            $user->roles()->syncWithoutDetaching([$role->id=>['assigned_by_user_id'=>$user->id,'created_at'=>now()]]);
            $this->ensureRegisteredUser($user,$user);
            $this->audit->record($user,'access.platform_owner_bootstrapped',$user,['source'=>'stage7_installer'],null,$user->id);
        });
    }

    public function replaceRoles(User $actor, User $target, array $roleKeys, Request $request): User
    {
        $roleKeys=array_values(array_unique($roleKeys));
        $known=Role::query()->whereIn('key',$roleKeys)->get();
        if ($known->count() !== count($roleKeys)) throw ValidationException::withMessages(['role_keys'=>['One or more roles are unknown.']]);
        $targetHasSuperAdmin=$target->hasRole(self::ROLE_SUPER_ADMIN);
        $requestsSuperAdmin=in_array(self::ROLE_SUPER_ADMIN,$roleKeys,true);
        if (($requestsSuperAdmin !== $targetHasSuperAdmin) && ! $actor->is_platform_owner) {
            throw ValidationException::withMessages(['role_keys'=>['Only the platform owner may grant or remove Super Admin.']]);
        }
        if ($target->is_platform_owner && ! $requestsSuperAdmin) {
            throw ValidationException::withMessages(['role_keys'=>['The platform owner cannot lose Super Admin.']]);
        }
        if ($target->is_platform_owner && $actor->id !== $target->id && ! $actor->is_platform_owner) {
            throw ValidationException::withMessages(['role_keys'=>['Only the platform owner may change the platform owner roles.']]);
        }
        if (! in_array(self::ROLE_REGISTERED_USER,$roleKeys,true)) $roleKeys[]=self::ROLE_REGISTERED_USER;

        return DB::transaction(function () use ($actor,$target,$roleKeys,$request): User {
            $roles=Role::query()->whereIn('key',$roleKeys)->get();
            $sync=[];
            foreach($roles as $role) $sync[$role->id]=['assigned_by_user_id'=>$actor->id,'created_at'=>now()];
            $before=$target->roles()->pluck('key')->sort()->values()->all();
            $beforeAccountType=$target->account_type;
            $target->roles()->sync($sync);

            $wantsBroker=in_array('broker',$roleKeys,true);
            if ($wantsBroker && ! $target->isBrokerAccount()) {
                $target->forceFill([
                    'account_type'=>User::ACCOUNT_TYPE_BROKER,
                    'broker_verification_status'=>User::BROKER_VERIFICATION_NOT_SUBMITTED,
                    'broker_verification_submitted_at'=>null,
                    'broker_verified_at'=>null,
                    'broker_verified_by_user_id'=>null,
                    'broker_verification_note'=>null,
                ])->save();
            } elseif (! $wantsBroker && $target->isBrokerAccount()) {
                $target->forceFill([
                    'account_type'=>User::ACCOUNT_TYPE_REGULAR,
                    'broker_verification_status'=>User::BROKER_VERIFICATION_NOT_REQUIRED,
                    'broker_verification_submitted_at'=>null,
                    'broker_verified_at'=>null,
                    'broker_verified_by_user_id'=>null,
                    'broker_verification_note'=>null,
                ])->save();
            }

            $after=$target->roles()->pluck('key')->sort()->values()->all();
            $afterAccountType=$target->fresh()->account_type;
            $this->audit->record($actor,'access.roles_changed',$target,[
                'before'=>$before,
                'after'=>$after,
                'account_type_before'=>$beforeAccountType,
                'account_type_after'=>$afterAccountType,
            ],$request,$target->id);
            return $target->fresh(['roles','permissionOverrides.permission']);
        });
    }

    public function replaceOverrides(User $actor, User $target, array $overrides, Request $request): User
    {
        if ($target->is_platform_owner && $actor->id !== $target->id && ! $actor->is_platform_owner) {
            throw ValidationException::withMessages(['overrides'=>['Only the platform owner may change owner permission overrides.']]);
        }

        return DB::transaction(function () use ($actor,$target,$overrides,$request): User {
            $before=$target->permissionOverrides()->with('permission')->get()->map(fn($o)=>['key'=>$o->permission->key,'effect'=>$o->effect])->values()->all();
            $target->permissionOverrides()->delete();
            foreach($overrides as $item){
                $permission=Permission::query()->where('key',$item['permission_key'])->firstOrFail();
                UserPermissionOverride::query()->create([
                    'user_id'=>$target->id,'permission_id'=>$permission->id,'effect'=>$item['effect'],
                    'assigned_by_user_id'=>$actor->id,'reason'=>$item['reason'] ?? null,
                ]);
            }
            $fresh=$target->fresh(['roles','permissionOverrides.permission']);
            $after=$fresh->permissionOverrides->map(fn($o)=>['key'=>$o->permission->key,'effect'=>$o->effect])->values()->all();
            $this->audit->record($actor,'access.permission_overrides_changed',$target,['before'=>$before,'after'=>$after],$request,$target->id);
            return $fresh;
        });
    }

    public function changeStatus(User $actor, User $target, string $status, Request $request, ApiTokenService $tokens): User
    {
        if ($target->is_platform_owner && $status !== User::STATUS_ACTIVE) {
            throw ValidationException::withMessages(['account_status'=>['The platform owner cannot be suspended, banned, or demoted to pending verification.']]);
        }
        if ($status === User::STATUS_ACTIVE && $target->phone_verified_at === null) {
            throw ValidationException::withMessages(['account_status'=>['Phone verification is required before activating the account.']]);
        }

        return DB::transaction(function () use ($actor,$target,$status,$request,$tokens): User {
            $before=$target->account_status;
            $target->forceFill(['account_status'=>$status])->save();
            if (in_array($status,[User::STATUS_SUSPENDED,User::STATUS_BANNED,User::STATUS_PENDING_VERIFICATION],true)) $tokens->revokeAll($target);
            $this->audit->record($actor,'account.status_changed',$target,['before'=>$before,'after'=>$status],$request,$target->id);
            return $target->fresh(['roles','permissionOverrides.permission']);
        });
    }
}
