<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\PushDeviceController;
use App\Jobs\SendUserPushNotification;
use App\Models\User;
use App\Models\UserPushDevice;
use App\Services\FcmPushSender;
use App\Services\UserNotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

class PushLaunchPrepTest extends TestCase
{
    use RefreshDatabase;

    public function test_push_tokens_are_encrypted_at_rest_and_hash_is_queryable(): void
    {
        $user=$this->user();
        $token=str_repeat('token-',20).'abc';
        $device=UserPushDevice::query()->create([
            'user_id'=>$user->id,
            'platform'=>'android',
            'token'=>$token,
            'token_hash'=>hash('sha256',$token),
            'installation_hash'=>hash('sha256','install-1234567890'),
            'app_build'=>1126,
            'last_seen_at'=>now(),
        ]);

        $raw=DB::table('user_push_devices')->where('id',$device->id)->first();
        $this->assertNotSame($token,$raw->token);
        $this->assertStringNotContainsString($token,$raw->token);
        $this->assertSame(hash('sha256',$token),$raw->token_hash);
        $this->assertSame($token,$device->fresh()->token);
    }

    public function test_push_disabled_does_not_collect_device_tokens(): void
    {
        config()->set('push.enabled',false);
        $user=$this->user();
        $request=Request::create('/api/push/devices','POST',[
            'platform'=>'android',
            'token'=>str_repeat('token-',20),
            'installation_id'=>'installation-1234567890',
            'app_build'=>1127,
        ]);
        $request->setUserResolver(fn ()=>$user);

        try {
            app(PushDeviceController::class)->store($request);
            $this->fail('Disabled push registration should fail.');
        } catch (HttpException $error) {
            $this->assertSame(409,$error->getStatusCode());
        }

        $this->assertDatabaseCount('user_push_devices',0);
    }

    public function test_push_disabled_keeps_in_app_notification_without_queueing_external_delivery(): void
    {
        Bus::fake();
        config()->set('push.enabled',false);
        $user=$this->user();

        $notification=app(UserNotificationService::class)->create(
            $user->id,
            'message_received',
            'رسالة جديدة',
            'لديك رسالة جديدة.',
            'message_thread',
            77,
        );

        $this->assertNotNull($notification);
        $this->assertDatabaseHas('user_notifications',[
            'id'=>$notification->id,
            'user_id'=>$user->id,
            'type'=>'message_received',
        ]);
        Bus::assertNotDispatched(SendUserPushNotification::class);
    }

    public function test_push_enabled_queues_delivery_after_notification_creation(): void
    {
        Bus::fake();
        config()->set('push.enabled',true);
        $user=$this->user();

        $device=UserPushDevice::query()->create([
            'user_id'=>$user->id,
            'platform'=>'android',
            'token'=>str_repeat('active-token-',12),
            'token_hash'=>hash('sha256',str_repeat('active-token-',12)),
            'installation_hash'=>hash('sha256','active-installation-1234567890'),
            'app_build'=>1127,
            'last_seen_at'=>now(),
        ]);

        $notification=app(UserNotificationService::class)->create(
            $user->id,
            'listing_review_approved',
            'تم اعتماد الإعلان',
            'إعلانك جاهز.',
            'property',
            42,
        );

        Bus::assertDispatched(
            SendUserPushNotification::class,
            fn (SendUserPushNotification $job) =>
                $job->notificationId === $notification?->id &&
                $job->deviceId === $device->id,
        );
    }

    public function test_disabled_sender_never_requires_credentials_or_network(): void
    {
        Http::fake(fn () => Http::response(['unexpected'=>true],500));
        config()->set('push.enabled',false);
        $user=$this->user();
        $notification=app(UserNotificationService::class)->create(
            $user->id,
            'support_reply',
            'رد الدعم',
            'يوجد رد جديد.',
            'support_case',
            1,
        );

        $device=UserPushDevice::query()->create([
            'user_id'=>$user->id,
            'platform'=>'android',
            'token'=>str_repeat('disabled-token-',12),
            'token_hash'=>hash('sha256',str_repeat('disabled-token-',12)),
            'installation_hash'=>hash('sha256','disabled-installation-1234567890'),
            'app_build'=>1127,
            'last_seen_at'=>now(),
        ]);

        app(FcmPushSender::class)->send($notification,$device);

        Http::assertNothingSent();
    }

    private function user(): User
    {
        return User::query()->create([
            'name'=>'Push User',
            'email'=>'push-user@example.test',
            'phone'=>'+967733112233',
            'phone_verified_at'=>now(),
            'email_verified_at'=>now(),
            'password'=>Hash::make('StrongPass123!'),
            'account_type'=>User::ACCOUNT_TYPE_REGULAR,
            'account_status'=>User::STATUS_ACTIVE,
            'profile_completed_at'=>now(),
        ]);
    }
}
