<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AccountErasureService;
use App\Services\ApiTokenService;
use App\Services\VerificationCodeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

class AccountErasureAuthRaceTest extends TestCase
{
    use RefreshDatabase;

    private function user(): User
    {
        Storage::fake('local');
        return User::create(['name'=>'Synthetic race actor','email'=>'erasure-race@example.test','phone'=>'+12025550149',
            'password'=>'fixture-only','account_status'=>User::STATUS_ACTIVE,'phone_verified_at'=>now(),
            'email_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2]);
    }

    private function erase(User $user): void
    {
        app(AccountErasureService::class)->erase($user,Request::create('/api/account','DELETE'));
    }

    public function test_stale_user_cannot_issue_a_new_token_after_erasure(): void
    {
        $user=$this->user(); $this->erase($user);
        try { app(ApiTokenService::class)->issue($user,Request::create('/api/auth/login'));$this->fail('Deleted actor issued token'); }
        catch (HttpException $error) { $this->assertSame(403,$error->getStatusCode()); }
        $this->assertDatabaseCount('api_tokens',0);
    }

    public function test_existing_token_cannot_authenticate_a_deleted_account_even_if_a_stale_row_survived(): void
    {
        $user=$this->user();$token=app(ApiTokenService::class)->issue($user,Request::create('/'))['plain_text_token'];
        $user->update(['account_status'=>User::STATUS_DELETED]);
        $this->withToken($token)->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_erasure_between_phone_otp_and_login_completion_cannot_resurrect_identity(): void
    {
        $user=$this->user();$phone=$user->phone;
        $this->mock(VerificationCodeService::class)->shouldReceive('verify')->once()->andReturnUsing(fn ()=>$this->erase($user));
        $this->postJson('/api/auth/whatsapp/verify',['phone'=>$phone,'code'=>'123456'])->assertForbidden();
        $this->assertSame(User::STATUS_DELETED,$user->fresh()->account_status);
        $this->assertNull($user->fresh()->phone_verified_at);
        $this->assertDatabaseCount('api_tokens',0);
    }

    public function test_erasure_between_email_otp_and_login_completion_cannot_issue_a_session(): void
    {
        $user=$this->user();$email=$user->email;
        $this->mock(VerificationCodeService::class)->shouldReceive('verify')->once()->andReturnUsing(fn ()=>$this->erase($user));
        $this->postJson('/api/auth/email/login',['email'=>$email,'code'=>'123456'])->assertForbidden();
        $this->assertSame(User::STATUS_DELETED,$user->fresh()->account_status);
        $this->assertNull($user->fresh()->email_verified_at);
        $this->assertDatabaseCount('api_tokens',0);
    }

    public function test_erased_account_cannot_gain_a_new_challenge_from_a_stale_request(): void
    {
        $user=$this->user();$phone=$user->phone;$this->erase($user);
        try { app(VerificationCodeService::class)->create($user,'phone',$phone);$this->fail('Deleted actor gained challenge'); }
        catch (HttpException $error) { $this->assertSame(403,$error->getStatusCode()); }
        $this->assertDatabaseCount('verification_challenges',0);
    }
}
