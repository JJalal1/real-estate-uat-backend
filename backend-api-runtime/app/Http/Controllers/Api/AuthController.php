<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AccountVerificationProfile;
use App\Models\User;
use App\Models\VerificationChallenge;
use App\Services\AccessControlService;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\LegacyOwnershipService;
use App\Services\VerificationCodeService;
use App\Services\WhatsAppVerificationSender;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(
        private readonly ApiTokenService $tokens,
        private readonly VerificationCodeService $verification,
        private readonly LegacyOwnershipService $legacyOwnership,
        private readonly AccessControlService $access,
        private readonly AuditLogService $audit,
        private readonly WhatsAppVerificationSender $whatsapp,
    ) {}

    public function register(Request $request): JsonResponse
    {
        // Legacy email/password registration remains available only to the local/test
        // regression harness. Current account creation uses the unified WhatsApp flow;
        // publishing identity is selected later through account verification.
        abort_unless(app()->environment('local', 'testing'), 410, 'Legacy registration is retired. Use WhatsApp registration.');
        $this->normalizeIdentityInput($request);
        $v = $request->validate([
            'name'=>['required','string','min:2','max:120'],
            'email'=>['required','email','max:190','unique:users,email'],
            'phone'=>['required','string','max:32','regex:/^\+?[0-9]{7,20}$/','unique:users,phone'],
            'password'=>['required','string','min:8','max:128','confirmed'],
            'legacy_owner_key'=>['nullable','string','min:32','max:96'],
        ]);
        $email = Str::lower(trim((string)$v['email']));
        $phone = $this->normalizePhone((string)$v['phone']);

        $result = DB::transaction(function () use ($request,$v,$email,$phone) {
            $user = User::query()->create([
                'name'=>trim((string)$v['name']),
                'email'=>$email,
                'phone'=>$phone,
                'password'=>Hash::make((string)$v['password']),
                'account_type'=>User::ACCOUNT_TYPE_REGULAR,
                'identity_policy_version'=>1,
                'broker_verification_status'=>User::BROKER_VERIFICATION_NOT_REQUIRED,
                'account_status'=>User::STATUS_PENDING_VERIFICATION,
            ]);
            $this->access->ensureRegisteredUser($user);
            $claimed = $this->legacyOwnership->claim($user,$v['legacy_owner_key'] ?? null);
            $token = $this->tokens->issue($user,$request);
            $this->audit->record($user,'auth.registered',$user,['legacy_listings_claimed'=>$claimed],$request,$user->id);
            return compact('user','claimed','token');
        });

        return response()->json([
            'message'=>'Account created. Verify the phone number to activate listing actions.',
            'data'=>[
                'user'=>$this->userData($result['user']->fresh(['roles','permissionOverrides.permission'])),
                'token'=>$result['token']['plain_text_token'],
                'token_expires_at'=>$result['token']['expires_at'],
                'legacy_listings_claimed'=>$result['claimed'],
            ],
        ],201);
    }

    public function startWhatsApp(Request $request): JsonResponse
    {
        $this->normalizeIdentityInput($request);
        $v = $request->validate([
            'intent'=>['required',Rule::in(['continue','register','login'])],
            'account_type'=>['nullable',Rule::in([User::ACCOUNT_TYPE_REGULAR,User::ACCOUNT_TYPE_BROKER])],
            'name'=>['nullable','string','max:120'],
            'phone'=>['required','string','max:32','regex:/^\+?[0-9]{7,20}$/'],
        ]);
        $intent=(string)$v['intent'];
        $phone=$this->normalizePhone((string)$v['phone']);
        $accountType=(string)($v['account_type'] ?? User::ACCOUNT_TYPE_REGULAR);
        $createdNow=false;

        if($intent==='continue'){
            $user=User::query()->where('phone',$phone)->first();
            if(!$user){
                $createdNow=true;
                $user=DB::transaction(function()use($phone){
                    $user=User::query()->create([
                        'name'=>'مستخدم جديد',
                        'email'=>$this->phoneOnlyPlaceholderEmail($phone),
                        'phone'=>$phone,
                        'password'=>Hash::make(Str::random(64)),
                        'account_type'=>User::ACCOUNT_TYPE_REGULAR,
                        'identity_policy_version'=>2,
                        'account_status'=>User::STATUS_PENDING_VERIFICATION,
                        'broker_verification_status'=>User::BROKER_VERIFICATION_NOT_REQUIRED,
                        'profile_completed_at'=>null,
                    ]);
                    $this->access->ensureRegisteredUser($user);
                    return $user;
                });
            }
        }elseif($intent==='register'){
            $name=trim((string)($v['name']??''));
            $this->validateFullName($name,$accountType);
            $user=User::query()->where('phone',$phone)->first();
            if($user){
                if($user->account_type!==$accountType){
                    throw ValidationException::withMessages(['account_type'=>['رقم واتساب مسجل بنوع حساب مختلف.']]);
                }
                if($user->phone_verified_at!==null){
                    throw ValidationException::withMessages(['phone'=>['هذا الرقم مسجل مسبقاً. اختر تسجيل الدخول.']]);
                }
                $user->forceFill(['name'=>$name,'identity_policy_version'=>1,'profile_completed_at'=>now()])->save();
            }else{
                $user=DB::transaction(function()use($name,$phone,$accountType,&$createdNow){
                    $createdNow=true;
                    $user=User::query()->create([
                        'name'=>$name,
                        'email'=>$this->phoneOnlyPlaceholderEmail($phone),
                        'phone'=>$phone,
                        'password'=>Hash::make(Str::random(64)),
                        'account_type'=>$accountType,
                        'identity_policy_version'=>1,
                        'account_status'=>User::STATUS_PENDING_VERIFICATION,
                        'broker_verification_status'=>$accountType===User::ACCOUNT_TYPE_BROKER
                            ? User::BROKER_VERIFICATION_NOT_SUBMITTED
                            : User::BROKER_VERIFICATION_NOT_REQUIRED,
                        'profile_completed_at'=>now(),
                    ]);
                    $this->access->ensureRegisteredUser($user);
                    return $user;
                });
            }
        }else{
            $user=User::query()->where('phone',$phone)->first();
            if(!$user){
                throw ValidationException::withMessages(['phone'=>['لا يوجد حساب بهذا الرقم. أنشئ حساباً جديداً أولاً.']]);
            }
            if(array_key_exists('account_type',$v) && $user->account_type!==$accountType){
                throw ValidationException::withMessages(['account_type'=>['نوع الحساب لا يطابق الحساب المسجل لهذا الرقم.']]);
            }
        }

        if($user->account_status===User::STATUS_SUSPENDED){
            return response()->json(['message'=>'This account is suspended.','code'=>'ACCOUNT_SUSPENDED'],403);
        }
        if($user->account_status===User::STATUS_BANNED){
            return response()->json(['message'=>'This account is banned.','code'=>'ACCOUNT_BANNED'],403);
        }

        try{
            $created=$this->verification->create($user,VerificationChallenge::PURPOSE_PHONE,$phone);
            $this->whatsapp->sendCode($phone,(string)$created['code']);
        }catch(\Throwable $e){
            if($createdNow){
                try{$user->delete();}catch(\Throwable){}
            }
            throw $e;
        }
        $this->audit->record($user,'auth.whatsapp_code_requested',$user,[
            'intent'=>$intent,
            'unified_login'=>$intent==='continue',
        ],$request,$user->id);

        return response()->json([
            'message'=>'Verification code sent by WhatsApp.',
            'data'=>[
                'phone'=>$phone,
                'intent'=>$intent,
                'account_type'=>$user->account_type,
                'is_new_account'=>$createdNow,
                'expires_in_minutes'=>VerificationCodeService::EXPIRES_MINUTES,
                'debug_code'=>$created['debug_code'],
            ],
        ]);
    }

    public function verifyWhatsApp(Request $request): JsonResponse
    {
        $this->normalizeIdentityInput($request);
        $v=$request->validate([
            'phone'=>['required','string','max:32','regex:/^\+?[0-9]{7,20}$/'],
            'account_type'=>['nullable',Rule::in([User::ACCOUNT_TYPE_REGULAR,User::ACCOUNT_TYPE_BROKER])],
            'code'=>['required','digits:6'],
            'legacy_owner_key'=>['nullable','string','min:32','max:96'],
        ]);
        $phone=$this->normalizePhone((string)$v['phone']);
        $user=User::query()->where('phone',$phone)->first();
        if(!$user || (array_key_exists('account_type',$v) && $user->account_type!==(string)$v['account_type'])){
            throw ValidationException::withMessages(['code'=>['رمز التحقق غير صالح أو انتهت صلاحيته.']]);
        }
        if($user->account_status===User::STATUS_SUSPENDED){
            return response()->json(['message'=>'This account is suspended.','code'=>'ACCOUNT_SUSPENDED'],403);
        }
        if($user->account_status===User::STATUS_BANNED){
            return response()->json(['message'=>'This account is banned.','code'=>'ACCOUNT_BANNED'],403);
        }

        $this->verification->verify($user,VerificationChallenge::PURPOSE_PHONE,$phone,(string)$v['code']);
        $user->forceFill([
            'phone_verified_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,
            'last_login_at'=>now(),
        ])->save();
        $this->access->ensureRegisteredUser($user);
        $claimed=$this->legacyOwnership->claim($user,$v['legacy_owner_key']??null);
        $token=$this->tokens->issue($user,$request);
        $this->audit->record($user,'auth.whatsapp_verified',$user,[
            'unified_login'=>!array_key_exists('account_type',$v),
            'legacy_listings_claimed'=>$claimed,
        ],$request,$user->id);

        return response()->json(['message'=>'WhatsApp verification completed.','data'=>[
            'user'=>$this->userData($user->fresh(['roles','permissionOverrides.permission','accountVerificationProfile.documents'])),
            'token'=>$token['plain_text_token'],
            'token_expires_at'=>$token['expires_at'],
            'legacy_listings_claimed'=>$claimed,
        ]]);
    }

    public function login(Request $request): JsonResponse
    {
        $v = $request->validate([
            'login'=>['required','string','max:190'],
            'password'=>['required','string','max:128'],
            'legacy_owner_key'=>['nullable','string','min:32','max:96'],
        ]);
        $login=(string)$v['login'];
        $user = $this->findByLogin($login);
        if (! $user || ! Hash::check((string)$v['password'],$user->password)) {
            $this->audit->record(null,'auth.login_failed',null,['login_fingerprint'=>$this->audit->loginFingerprint($login),'reason'=>'invalid_credentials'],$request,$user?->id);
            throw ValidationException::withMessages(['login'=>['The login details are incorrect.']]);
        }
        if ($user->account_status === User::STATUS_SUSPENDED) {
            $this->audit->record($user,'auth.login_blocked',$user,['reason'=>'suspended'],$request,$user->id);
            return response()->json(['message'=>'This account is suspended.','code'=>'ACCOUNT_SUSPENDED'],403);
        }
        if ($user->account_status === User::STATUS_BANNED) {
            $this->audit->record($user,'auth.login_blocked',$user,['reason'=>'banned'],$request,$user->id);
            return response()->json(['message'=>'This account is banned.','code'=>'ACCOUNT_BANNED'],403);
        }

        $claimed = $this->legacyOwnership->claim($user,$v['legacy_owner_key'] ?? null);
        $user->forceFill(['last_login_at'=>now()])->save();
        $this->access->ensureRegisteredUser($user);
        $token = $this->tokens->issue($user,$request);
        $this->audit->record($user,'auth.login_succeeded',$user,['legacy_listings_claimed'=>$claimed],$request,$user->id);

        return response()->json(['message'=>'Logged in.','data'=>[
            'user'=>$this->userData($user->fresh(['roles','permissionOverrides.permission'])),
            'token'=>$token['plain_text_token'],
            'token_expires_at'=>$token['expires_at'],
            'legacy_listings_claimed'=>$claimed,
        ]]);
    }

    public function logout(Request $request): JsonResponse
    {
        /** @var User $user */
        $user=$request->user();
        $this->audit->record($user,'auth.logout',$user,[],$request,$user->id);
        $this->tokens->revokeCurrent($request);
        return response()->json(['message'=>'Logged out.']);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['data'=>['user'=>$this->userData($request->user())]]);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->normalizeIdentityInput($request);
        $v = $request->validate([
            'name'=>['sometimes','string','min:2','max:120'],
            'email'=>['sometimes','email','max:190',Rule::unique('users','email')->ignore($user->id)],
            'phone'=>['sometimes','string','max:32','regex:/^\+?[0-9]{7,20}$/',Rule::unique('users','phone')->ignore($user->id)],
        ]);
        $changed=[];
        if (array_key_exists('name',$v)) {
            $name=trim((string)$v['name']);
            $profile=$user->verificationProfile();
            $nameChanged=preg_replace('/\s+/u',' ',$name)!==preg_replace('/\s+/u',' ',trim((string)$user->name));
            if ($nameChanged && $profile && in_array($profile->status,[
                AccountVerificationProfile::STATUS_PENDING,
                AccountVerificationProfile::STATUS_APPROVED,
            ],true)) {
                throw ValidationException::withMessages([
                    'name'=>['لا يمكن تغيير الاسم أثناء مراجعة الهوية أو بعد اعتمادها. اطلب من فريق الدعم إعادة فتح التحقق إذا احتجت تصحيح الاسم.'],
                ]);
            }
            if ((int) $user->identity_policy_version >= 2 || $user->profile_completed_at === null) {
                $this->validateUnifiedFullName($name);
                $user->profile_completed_at = now();
            } else {
                $this->validateFullName($name,$user->account_type ?? User::ACCOUNT_TYPE_REGULAR);
            }
            $user->name=$name;
            $changed[]='name';
        }
        if (array_key_exists('email',$v)) { $user->email = Str::lower(trim((string)$v['email'])); $changed[]='email'; }
        if (array_key_exists('phone',$v)) {
            $phone = $this->normalizePhone((string)$v['phone']);
            if ($phone !== $user->phone) {
                $user->phone = $phone;
                $user->phone_verified_at = null;
                $changed[]='phone';
                if (! in_array($user->account_status,[User::STATUS_BANNED,User::STATUS_SUSPENDED],true)) {
                    $user->account_status = User::STATUS_PENDING_VERIFICATION;
                }
            }
        }
        $user->save();
        $this->audit->record($user,'account.profile_updated',$user,['changed_fields'=>$changed],$request,$user->id);
        return response()->json(['message'=>'Profile updated.','data'=>['user'=>$this->userData($user->fresh(['roles','permissionOverrides.permission']))]]);
    }

    public function requestPhoneVerification(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if ($user->phone === null) throw ValidationException::withMessages(['phone'=>['Add a phone number first.']]);
        if ($user->isActive()) return response()->json(['message'=>'Phone is already verified.','data'=>['debug_code'=>null]]);
        $created = $this->verification->create($user,VerificationChallenge::PURPOSE_PHONE,$user->phone);
        $this->whatsapp->sendCode($user->phone,(string)$created['code']);
        $this->audit->record($user,'auth.phone_verification_requested',$user,[],$request,$user->id);
        return response()->json(['message'=>'Verification code created.','data'=>[
            'expires_in_minutes'=>VerificationCodeService::EXPIRES_MINUTES,
            'debug_code'=>$created['debug_code'],
        ]]);
    }

    public function verifyPhone(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $v = $request->validate(['code'=>['required','digits:6']]);
        if ($user->phone === null) throw ValidationException::withMessages(['phone'=>['No phone number is configured.']]);
        $this->verification->verify($user,VerificationChallenge::PURPOSE_PHONE,$user->phone,(string)$v['code']);
        $user->forceFill(['phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE])->save();
        $this->audit->record($user,'auth.phone_verified',$user,[],$request,$user->id);
        return response()->json(['message'=>'Phone verified.','data'=>['user'=>$this->userData($user->fresh(['roles','permissionOverrides.permission']))]]);
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $v = $request->validate(['login'=>['required','string','max:190']]);
        $login=(string)$v['login'];
        $user = $this->findByLogin($login);
        $debugCode = null;
        if ($user && $user->phone !== null) {
            $created = $this->verification->create($user,VerificationChallenge::PURPOSE_PASSWORD_RESET,$user->phone);
            $this->whatsapp->sendCode($user->phone,(string)$created['code']);
            $debugCode = $created['debug_code'];
        }
        $this->audit->record($user,'auth.password_reset_requested',$user,['login_fingerprint'=>$this->audit->loginFingerprint($login),'account_found'=>$user !== null],$request,$user?->id);
        return response()->json(['message'=>'If the account exists, a recovery code has been created.','data'=>['debug_code'=>$debugCode]]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $v = $request->validate([
            'login'=>['required','string','max:190'],
            'code'=>['required','digits:6'],
            'password'=>['required','string','min:8','max:128','confirmed'],
        ]);
        $user = $this->findByLogin((string)$v['login']);
        if (! $user || $user->phone === null) throw ValidationException::withMessages(['code'=>['The recovery code is invalid or expired.']]);
        $this->verification->verify($user,VerificationChallenge::PURPOSE_PASSWORD_RESET,$user->phone,(string)$v['code']);
        $user->forceFill(['password'=>Hash::make((string)$v['password'])])->save();
        $this->tokens->revokeAll($user);
        $this->audit->record($user,'auth.password_reset_completed',$user,[],$request,$user->id);
        return response()->json(['message'=>'Password reset completed. Sign in again.']);
    }

    public function claimLegacyOwnership(Request $request): JsonResponse
    {
        $v = $request->validate(['legacy_owner_key'=>['required','string','min:32','max:96']]);
        $claimed = $this->legacyOwnership->claim($request->user(),(string)$v['legacy_owner_key']);
        $this->audit->record($request->user(),'listing.legacy_claimed',$request->user(),['listings_claimed'=>$claimed],$request,$request->user()->id);
        return response()->json(['message'=>'Legacy ownership claim completed.','data'=>['legacy_listings_claimed'=>$claimed]]);
    }

    private function normalizeIdentityInput(Request $request): void
    {
        $input = [];
        if ($request->filled('email')) $input['email'] = Str::lower(trim((string) $request->input('email')));
        if ($request->filled('phone')) $input['phone'] = $this->normalizePhone((string) $request->input('phone'));
        if ($input !== []) $request->merge($input);
    }

    private function findByLogin(string $login): ?User
    {
        $login = trim($login);
        $phone = $this->tryNormalizePhone($login);
        return User::query()->where(function ($q) use ($login,$phone) {
            $q->where('email',Str::lower($login));
            if ($phone !== null) $q->orWhere('phone',$phone);
        })->first();
    }

    private function normalizePhone(string $phone): string
    {
        $phone = strtr(trim($phone), [
            '٠'=>'0','١'=>'1','٢'=>'2','٣'=>'3','٤'=>'4','٥'=>'5','٦'=>'6','٧'=>'7','٨'=>'8','٩'=>'9',
            '۰'=>'0','۱'=>'1','۲'=>'2','۳'=>'3','۴'=>'4','۵'=>'5','۶'=>'6','۷'=>'7','۸'=>'8','۹'=>'9',
            '＋'=>'+','﹢'=>'+',
        ]);
        $phone = preg_replace('/[\p{Cf}\p{Z}\s\-().]/u','',$phone) ?? '';
        if (str_starts_with($phone,'00')) $phone = '+'.substr($phone,2);
        if (! preg_match('/^\+?[0-9]{7,20}$/',$phone)) throw ValidationException::withMessages(['phone'=>['Use digits and an optional leading +.']]);
        return $phone;
    }

    private function tryNormalizePhone(string $value): ?string
    {
        try { return $this->normalizePhone($value); }
        catch (ValidationException) { return null; }
    }

    private function validateFullName(string $name, string $accountType): void
    {
        $parts=preg_split('/\s+/u',trim($name),-1,PREG_SPLIT_NO_EMPTY)?:[];
        if($accountType===User::ACCOUNT_TYPE_BROKER){
            if(count($parts)<3 || count($parts)>4){
                throw ValidationException::withMessages(['name'=>['اسم الدلال يجب أن يكون ثلاثياً أو رباعياً.']]);
            }
            return;
        }
        if(count($parts)!==3){
            throw ValidationException::withMessages(['name'=>['اسم المستخدم العادي يجب أن يكون ثلاثياً.']]);
        }
    }

    private function validateUnifiedFullName(string $name): void
    {
        $parts=preg_split('/\s+/u',trim($name),-1,PREG_SPLIT_NO_EMPTY)?:[];
        if(count($parts)!==4){
            throw ValidationException::withMessages(['name'=>['أدخل الاسم الرباعي كما هو في وثيقة الهوية.']]);
        }
    }

    private function verificationProfileData(User $user): array
    {
        $profile=$user->accountVerificationProfile;
        if(!$profile){
            return [
                'type'=>null,
                'status'=>'not_submitted',
                'submitted_at'=>null,
                'reviewed_at'=>null,
                'note'=>null,
                'flags'=>[
                    'identity_reviewed'=>false,
                    'professional_document_reviewed'=>false,
                    'commercial_register_reviewed'=>false,
                    'office_documents_reviewed'=>false,
                    'office_location_registered'=>false,
                ],
            ];
        }
        $kinds=$profile->documents->pluck('kind');
        $approved=$profile->isApproved();
        return [
            'type'=>$profile->type,
            'status'=>$profile->status,
            'submitted_at'=>$profile->submitted_at?->toIso8601String(),
            'reviewed_at'=>$profile->reviewed_at?->toIso8601String(),
            'note'=>$profile->review_note,
            'flags'=>[
                'identity_reviewed'=>$approved,
                'professional_document_reviewed'=>$approved && $profile->type==='broker' && $kinds->contains('professional_license'),
                'commercial_register_reviewed'=>$approved && $profile->type==='office' && $kinds->contains('commercial_register'),
                'office_documents_reviewed'=>$approved && $profile->type==='office' && $kinds->contains('office_license'),
                'office_location_registered'=>$approved && $profile->type==='office' && isset(($profile->details ?? [])['latitude'],($profile->details ?? [])['longitude']),
            ],
        ];
    }

    private function phoneOnlyPlaceholderEmail(string $phone): string
    {
        return 'wa_'.substr(hash('sha256',$phone.'|'.Str::uuid()->toString()),0,32).'@phone.local.invalid';
    }

    private function userData(User $user): array
    {
        $user->loadMissing(['roles','permissionOverrides.permission','accountVerificationProfile.documents']);
        return [
            'id'=>(int)$user->id,
            'name'=>$user->name,
            'email'=>$user->email,
            'phone'=>$user->phone,
            'account_type'=>$user->account_type ?? User::ACCOUNT_TYPE_REGULAR,
            'phone_verified_at'=>$user->phone_verified_at?->toIso8601String(),
            'profile_completed_at'=>$user->profile_completed_at?->toIso8601String(),
            'account_status'=>$user->account_status,
            'broker_verification_status'=>$user->broker_verification_status ?? User::BROKER_VERIFICATION_NOT_REQUIRED,
            'broker_verification_submitted_at'=>$user->broker_verification_submitted_at?->toIso8601String(),
            'broker_verified_at'=>$user->broker_verified_at?->toIso8601String(),
            'broker_verification_note'=>$user->broker_verification_note,
            'last_login_at'=>$user->last_login_at?->toIso8601String(),
            'created_at'=>$user->created_at?->toIso8601String(),
            'is_platform_owner'=>(bool)$user->is_platform_owner,
            'verification_profile'=>$this->verificationProfileData($user),
            'roles'=>$user->roleKeys(),
            'permissions'=>$user->effectivePermissionKeys(),
        ];
    }
}
