<?php
namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use LogicException;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    public const STATUS_ACTIVE = 'active';
    public const STATUS_PENDING_VERIFICATION = 'pending_verification';
    public const STATUS_SUSPENDED = 'suspended';
    public const STATUS_BANNED = 'banned';

    public const ACCOUNT_TYPE_REGULAR = 'regular';
    public const ACCOUNT_TYPE_BROKER = 'broker';

    public const BROKER_VERIFICATION_NOT_REQUIRED = 'not_required';
    public const BROKER_VERIFICATION_NOT_SUBMITTED = 'not_submitted';
    public const BROKER_VERIFICATION_PENDING = 'pending';
    public const BROKER_VERIFICATION_APPROVED = 'approved';
    public const BROKER_VERIFICATION_REJECTED = 'rejected';

    protected $fillable = [
        'name','email','phone','password','account_type','identity_policy_version','account_status','phone_verified_at','last_login_at','is_platform_owner',
        'broker_verification_status','broker_verification_submitted_at','broker_verified_at','broker_verified_by_user_id','broker_verification_note',
    ];

    protected $hidden = ['password','remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'phone_verified_at' => 'datetime',
            'last_login_at' => 'datetime',
            'broker_verification_submitted_at' => 'datetime',
            'broker_verified_at' => 'datetime',
            'is_platform_owner' => 'boolean',
            'identity_policy_version' => 'integer',
            'password' => 'hashed',
        ];
    }

    protected static function booted(): void
    {
        static::deleting(function (User $user): void {
            if ($user->is_platform_owner) {
                throw new LogicException('The platform owner account cannot be deleted.');
            }
        });
    }

    public function properties(): HasMany { return $this->hasMany(Property::class); }
    public function apiTokens(): HasMany { return $this->hasMany(ApiToken::class); }
    public function verificationChallenges(): HasMany { return $this->hasMany(VerificationChallenge::class); }
    public function roles(): BelongsToMany { return $this->belongsToMany(Role::class,'user_role')->withPivot(['assigned_by_user_id','created_at']); }
    public function permissionOverrides(): HasMany { return $this->hasMany(UserPermissionOverride::class); }
    public function brokerCellAssignments(): HasMany { return $this->hasMany(BrokerCellAssignment::class, 'broker_user_id'); }
    public function brokerVerificationDocuments(): HasMany { return $this->hasMany(BrokerVerificationDocument::class, 'user_id'); }
    public function listingComments(): HasMany { return $this->hasMany(ListingComment::class, 'author_user_id'); }
    public function supportCases(): HasMany { return $this->hasMany(SupportCase::class, 'requester_user_id'); }
    public function messageParticipants(): HasMany { return $this->hasMany(MessageThreadParticipant::class, 'user_id'); }
    public function appNotifications(): HasMany { return $this->hasMany(UserNotification::class, 'user_id'); }

    public function isActive(): bool
    {
        return $this->account_status === self::STATUS_ACTIVE && $this->phone_verified_at !== null;
    }

    public function isBrokerAccount(): bool
    {
        return $this->account_type === self::ACCOUNT_TYPE_BROKER;
    }

    public function isRegularAccount(): bool
    {
        return ! $this->isBrokerAccount();
    }

    public function isBrokerVerified(): bool
    {
        return $this->isBrokerAccount()
            && $this->broker_verification_status === self::BROKER_VERIFICATION_APPROVED
            && $this->broker_verified_at !== null;
    }

    public function canCreateListings(): bool
    {
        if (! $this->isActive()) return false;
        return $this->isRegularAccount() || $this->isBrokerVerified();
    }

    public function hasRole(string $key): bool
    {
        if ($this->relationLoaded('roles')) return $this->roles->contains('key',$key);
        return $this->roles()->where('roles.key',$key)->exists();
    }

    public function hasPermission(string $key): bool
    {
        if ($this->is_platform_owner || $this->hasRole('super_admin')) return true;
        $permission=Permission::query()->where('key',$key)->first();
        if (! $permission) return false;
        $override=$this->permissionOverrides()->where('permission_id',$permission->id)->value('effect');
        if ($override === 'deny') return false;
        if ($override === 'allow') return true;
        return $this->roles()->whereHas('permissions',fn($q)=>$q->where('permissions.id',$permission->id))->exists();
    }

    public function roleKeys(): array
    {
        if (! $this->relationLoaded('roles')) $this->load('roles');
        return $this->roles->pluck('key')->sort()->values()->all();
    }

    public function effectivePermissionKeys(): array
    {
        if ($this->is_platform_owner || $this->hasRole('super_admin')) {
            return Permission::query()->orderBy('key')->pluck('key')->all();
        }
        $roleIds=$this->roles()->pluck('roles.id')->all();
        $rolePermissionKeys=Permission::query()
            ->whereHas('roles',fn($q)=>$q->whereIn('roles.id',$roleIds))
            ->pluck('key')->all();
        $effective=array_fill_keys($rolePermissionKeys,true);
        foreach($this->permissionOverrides()->with('permission')->get() as $override){
            if ($override->effect === 'allow') $effective[$override->permission->key]=true;
            if ($override->effect === 'deny') unset($effective[$override->permission->key]);
        }
        $keys=array_keys($effective); sort($keys); return $keys;
    }
}
