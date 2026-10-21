<?php
namespace Tests\Feature;

use App\Models\User;
use App\Models\VerificationChallenge;
use App\Services\EmailVerificationSender;
use App\Services\VerificationCodeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

class EmailLoginAndNameTest extends TestCase
{
    use RefreshDatabase;
    private const NAME = 'أحمد علي محمد صالح';
    private const EMAIL = 'email-login@example.test';

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('email-otp:'.hash('sha256', self::EMAIL));
    }

    public function test_whatsapp_name_is_saved_only_after_valid_code_and_existing_names_are_preserved(): void
    {
        $phone = '+967700000991';
        $start = $this->postJson('/api/auth/whatsapp/start', ['intent'=>'continue','phone'=>$phone,'name'=>self::NAME])->assertOk();
        $user = User::query()->where('phone',$phone)->firstOrFail();
        $this->assertSame('مستخدم جديد', $user->name);
        $this->assertNull($user->profile_completed_at);
        $code = $start->json('data.debug_code');
        $this->postJson('/api/auth/whatsapp/verify', ['phone'=>$phone,'name'=>self::NAME,'code'=>$code])->assertOk()
            ->assertJsonPath('data.user.name', self::NAME)->assertJsonPath('data.user.account_status','active');
        $this->assertNotNull($user->fresh()->profile_completed_at);
        $start = $this->postJson('/api/auth/whatsapp/start', ['intent'=>'continue','phone'=>$phone])->assertOk();
        $this->postJson('/api/auth/whatsapp/verify', ['phone'=>$phone,'name'=>'اسم آخر مختلف تمامًا','code'=>$start->json('data.debug_code')])
            ->assertOk()->assertJsonPath('data.user.name', self::NAME);
    }

    public function test_email_code_creates_a_normal_session_without_verifying_phone_or_publishing(): void
    {
        $start = $this->start();
        $user = User::query()->where('email',self::EMAIL)->firstOrFail();
        $this->assertNull($user->email_verified_at);
        $this->assertSame('مستخدم جديد',$user->name);
        $this->postJson('/api/auth/email/login', ['email'=>self::EMAIL,'code'=>'000000','name'=>self::NAME])->assertUnprocessable();
        $this->assertNull($user->fresh()->email_verified_at);
        $login = $this->verify($start)->assertOk()->assertJsonPath('data.user.name',self::NAME)
            ->assertJsonPath('data.user.phone_verified_at',null)->assertJsonPath('data.user.account_status','pending_verification')
            ->assertJsonPath('data.user.account_type','regular');
        $this->assertNotNull($user->fresh()->email_verified_at);
        $this->assertFalse($user->fresh()->isActive());
        $headers = ['Authorization'=>'Bearer '.$login->json('data.token')];
        $this->withHeaders($headers)->getJson('/api/auth/me')->assertOk();
        $this->withHeaders($headers)->postJson('/api/properties',[])->assertForbidden();
        $this->verify($start)->assertUnprocessable();
        $this->assertSame(1,$user->apiTokens()->count());
    }

    public function test_existing_whatsapp_account_logs_in_without_a_name_or_a_duplicate_account(): void
    {
        $user = User::factory()->create(['phone'=>'+967700000991', 'phone_verified_at'=>now(),
            'name'=>self::NAME, 'profile_completed_at'=>now(), 'identity_policy_version'=>2, 'account_status'=>'active']);
        $count = User::query()->count();
        $start = $this->postJson('/api/auth/whatsapp/start', ['intent'=>'login', 'phone'=>$user->phone])
            ->assertOk()->assertJsonPath('data.is_new_account', false);
        $this->postJson('/api/auth/whatsapp/verify', ['phone'=>$user->phone, 'code'=>$start->json('data.debug_code')])
            ->assertOk()->assertJsonPath('data.user.id', $user->id)->assertJsonPath('data.user.name', self::NAME);
        $this->assertSame($count, User::query()->count());
        $this->assertNotNull($user->fresh()->profile_completed_at);
        $this->assertSame(1, $user->apiTokens()->count());
    }

    public function test_existing_verified_email_logs_in_without_a_name_and_keeps_the_same_account(): void
    {
        $user = User::factory()->create(['email'=>self::EMAIL, 'email_verified_at'=>now(),
            'phone'=>'+967700000992', 'phone_verified_at'=>now(), 'name'=>self::NAME,
            'profile_completed_at'=>now(), 'identity_policy_version'=>2, 'account_status'=>'active']);
        $count = User::query()->count();
        $start = $this->postJson('/api/auth/email/start', ['intent'=>'login', 'email'=>self::EMAIL])->assertOk();
        $this->postJson('/api/auth/email/login', ['email'=>self::EMAIL, 'code'=>$start->json('data.debug_code')])
            ->assertOk()->assertJsonPath('data.user.id', $user->id)->assertJsonPath('data.user.name', self::NAME);
        $this->assertSame($count, User::query()->count());
        $this->assertNotNull($user->fresh()->phone_verified_at);
        $this->assertNotNull($user->fresh()->profile_completed_at);
        $this->assertSame(1, $user->apiTokens()->count());
    }

    public function test_login_intent_never_creates_an_unknown_phone_or_email_account(): void
    {
        $count = User::query()->count();
        $this->postJson('/api/auth/whatsapp/start', ['intent'=>'login', 'phone'=>'+967700000991'])
            ->assertUnprocessable()->assertJsonValidationErrors('phone');
        $this->postJson('/api/auth/email/start', ['intent'=>'login', 'email'=>self::EMAIL])
            ->assertUnprocessable()->assertJsonValidationErrors('email');
        $this->assertSame($count, User::query()->count());
        $this->assertDatabaseCount('verification_challenges', 0);
        $this->assertDatabaseCount('api_tokens', 0);
    }

    public function test_expired_and_wrong_destination_codes_do_not_issue_tokens(): void
    {
        $start = $this->start();
        $this->postJson('/api/auth/email/login',['email'=>'other@example.test','code'=>$start->json('data.debug_code')])->assertUnprocessable();
        $this->travel(11)->minutes();
        $this->verify($start)->assertUnprocessable();
        $this->assertDatabaseCount('api_tokens',0);
    }

    public function test_five_wrong_attempts_lock_the_challenge_and_resend_invalidates_it(): void
    {
        $start = $this->start();
        for ($i=0;$i<5;$i++) $this->postJson('/api/auth/email/login',['email'=>self::EMAIL,'code'=>'000000'])->assertUnprocessable();
        $this->verify($start)->assertUnprocessable();
        $this->assertSame(5,(int)VerificationChallenge::query()->firstOrFail()->attempts);
        // The existing IP limiter also covers these failed submissions. A resend
        // waits for that minute window instead of bypassing the live throttle.
        $this->start()->assertStatus(429);
        $this->travel(61)->seconds();
        $next = $this->start()->assertOk();
        $this->assertNotNull(VerificationChallenge::query()->oldest('id')->firstOrFail()->consumed_at);
        $this->verify($next)->assertOk();
    }

    public function test_unverified_email_on_a_phone_account_cannot_be_used_for_login(): void
    {
        $user = User::factory()->create(['email'=>self::EMAIL,'email_verified_at'=>null,'phone'=>'+967700000992','phone_verified_at'=>now()]);
        $this->start()->assertJsonPath('data.debug_code',null);
        $this->assertSame(0,$user->verificationChallenges()->count());
        $this->postJson('/api/auth/email/login',['email'=>self::EMAIL,'code'=>'123456'])->assertUnprocessable();
    }

    public function test_signed_in_confirmation_allows_email_login_to_the_same_account_and_change_revokes_it(): void
    {
        $user = User::factory()->create(['email'=>self::EMAIL,'email_verified_at'=>null,'phone'=>'+967700000993',
            'phone_verified_at'=>now(),'account_status'=>'active','name'=>self::NAME,'profile_completed_at'=>now(),'identity_policy_version'=>2]);
        $this->postJson('/api/auth/email/request')->assertUnauthorized();
        $headers = $this->authHeaders($user);
        $this->withHeaders($headers)->postJson('/api/auth/email/request')->assertOk();
        $challenge = $user->verificationChallenges()->latest('id')->firstOrFail();
        // Tests get the generated secret from the delivery seam, not by persisting plaintext.
        $created = app(VerificationCodeService::class)->create($user,VerificationChallenge::PURPOSE_EMAIL,$user->email,allowUatCode:false);
        $this->withHeaders($headers)->postJson('/api/auth/email/verify',['code'=>$created['code']])->assertOk();
        $login = $this->start();
        $this->verify($login)->assertOk()->assertJsonPath('data.user.id',$user->id);
        $this->withHeaders($headers)->patchJson('/api/auth/profile',['email'=>'changed@example.test'])->assertOk();
        $this->assertNull($user->fresh()->email_verified_at);
        $this->assertNotNull($challenge->fresh()->consumed_at);
        $this->verify($login)->assertUnprocessable();
    }

    public function test_challenge_purposes_are_separate(): void
    {
        $start = $this->start();
        $user = User::query()->where('email',self::EMAIL)->firstOrFail();
        $this->withHeaders($this->authHeaders($user))->postJson('/api/auth/email/verify',['code'=>$start->json('data.debug_code')])->assertUnprocessable();
        $this->verify($start)->assertOk();
    }

    public function test_blocked_account_is_never_reactivated_by_email(): void
    {
        $start = $this->start();
        $user = User::query()->where('email',self::EMAIL)->firstOrFail();
        $user->forceFill(['account_status'=>'suspended'])->save();
        $this->verify($start)->assertForbidden();
        $this->assertDatabaseCount('api_tokens',0);
    }

    public function test_destination_limit_is_shared_across_ip_addresses(): void
    {
        for ($i=0;$i<5;$i++) $this->withServerVariables(['REMOTE_ADDR'=>'192.0.2.'.($i+1)])->start()->assertOk();
        $this->withServerVariables(['REMOTE_ADDR'=>'192.0.2.99'])->start()->assertStatus(429);
    }

    public function test_unconfigured_staging_mail_fails_closed_and_does_not_log_codes(): void
    {
        $this->app->instance('env','staging');
        config(['mail.default'=>'log']);
        $this->start()->assertStatus(503);
        $this->assertDatabaseCount('verification_challenges',0);
        $this->assertDatabaseMissing('users',['email'=>self::EMAIL]);
    }

    public function test_failed_delivery_consumes_the_challenge_without_a_token(): void
    {
        $sender = $this->mock(EmailVerificationSender::class);
        $sender->shouldReceive('ensureConfigured')->once();
        $sender->shouldReceive('sendCode')->once()->andThrow(new \Symfony\Component\HttpKernel\Exception\HttpException(503,'تعذر إرسال الرمز.'));
        $this->start()->assertStatus(503);
        $this->assertNotNull(VerificationChallenge::query()->firstOrFail()->consumed_at);
        $this->assertDatabaseCount('api_tokens',0);
    }

    private function start(): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/api/auth/email/start',['email'=>strtoupper(self::EMAIL),'name'=>self::NAME]);
    }
    private function authHeaders(User $user): array
    {
        $token = app(\App\Services\ApiTokenService::class)->issue($user, \Illuminate\Http\Request::create('/'));
        return ['Authorization'=>'Bearer '.$token['plain_text_token']];
    }
    private function verify($start): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/api/auth/email/login',['email'=>self::EMAIL,'code'=>$start->json('data.debug_code'),'name'=>self::NAME]);
    }
}
