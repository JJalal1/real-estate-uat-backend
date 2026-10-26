<?php

namespace Tests\Feature;

use App\Jobs\SendUserPushNotification;
use App\Models\User;
use App\Models\UserNotification;
use App\Models\UserNotificationPreference;
use App\Models\UserPushDevice;
use App\Services\FcmPushSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PushDeliveryLifecycleTest extends TestCase
{
    use RefreshDatabase;

    private function fixture(): array
    {
        $credentials=base64_encode(json_encode(['client_email'=>'synthetic@example.test','private_key'=>'unused-cached-test-key','project_id'=>'synthetic-project']));
        config(['push.enabled'=>true,'push.fcm.project_id'=>'synthetic-project','push.fcm.service_account_json_base64'=>$credentials]);
        Cache::store('file')->put('fcm-oauth-token:'.hash('sha256',$credentials),'synthetic-cached-oauth',60);
        Http::preventStrayRequests();
        $user=User::create(['name'=>'Synthetic push actor','email'=>'push-lifecycle@example.test','password'=>'fixture-only','account_status'=>User::STATUS_ACTIVE]);
        $notification=UserNotification::create(['user_id'=>$user->id,'type'=>'message_received','title'=>'رسالة اصطناعية','body'=>'نص خاص لا يطبع في السجل','created_at'=>now()]);
        $token=str_repeat('synthetic-private-token-',4);
        $device=UserPushDevice::create(['user_id'=>$user->id,'platform'=>'android','token'=>$token,'token_hash'=>hash('sha256',$token),'installation_hash'=>hash('sha256','synthetic-installation')]);
        return [$user,$notification,$device];
    }

    public function test_queued_delivery_respects_preference_revoked_after_enqueue(): void
    {
        [$user,$notification,$device]=$this->fixture();
        UserNotificationPreference::create(['user_id'=>$user->id,'messages'=>false]);
        Http::fake(['*'=>Http::response(['name'=>'synthetic-message'],200)]);
        (new SendUserPushNotification($notification->id,$device->id))->handle(app(FcmPushSender::class));
        Http::assertNothingSent();
    }

    public function test_queued_delivery_never_sends_for_suspended_account(): void
    {
        [$user,$notification,$device]=$this->fixture();
        $user->update(['account_status'=>User::STATUS_SUSPENDED]);
        Http::fake(['*'=>Http::response(['name'=>'synthetic-message'],200)]);
        (new SendUserPushNotification($notification->id,$device->id))->handle(app(FcmPushSender::class));
        Http::assertNothingSent();
    }

    public function test_generic_provider_404_does_not_disable_a_valid_registration(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response(['error'=>['status'=>'NOT_FOUND','message'=>'Project misconfigured']],404)]);
        try { app(FcmPushSender::class)->send($notification,$device); $this->fail('Configuration failure must be visible'); }
        catch (\RuntimeException $e) { $this->assertStringNotContainsString($device->token,$e->getMessage()); }
        $this->assertNull($device->fresh()->disabled_at);
    }

    public function test_unregistered_response_does_not_disable_a_token_refreshed_in_flight(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(function () use ($device) {
            $fresh=str_repeat('refreshed-token-',5);
            UserPushDevice::findOrFail($device->id)->forceFill(['token'=>$fresh,'token_hash'=>hash('sha256',$fresh)])->save();
            return Http::response(['error'=>['details'=>[['@type'=>'type.googleapis.com/google.firebase.fcm.v1.FcmError','errorCode'=>'UNREGISTERED']]]],404);
        });
        app(FcmPushSender::class)->send($notification,$device);
        $this->assertNull($device->fresh()->disabled_at);
        $this->assertSame(hash('sha256',str_repeat('refreshed-token-',5)),$device->fresh()->token_hash);
    }

    public function test_exact_unregistered_code_disables_only_the_original_registration(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response(['error'=>['details'=>[['@type'=>'type.googleapis.com/google.firebase.fcm.v1.FcmError','errorCode'=>'UNREGISTERED']]]],404)]);
        app(FcmPushSender::class)->send($notification,$device);
        $this->assertNotNull($device->fresh()->disabled_at);
    }

    public function test_throttling_exposes_bounded_retry_after_without_provider_secrets(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response(['private'=>'never log this'],429,['Retry-After'=>'180'])]);
        try { app(FcmPushSender::class)->send($notification,$device); $this->fail('Throttle must be retried'); }
        catch (\App\Services\PushDeliveryException $e) {
            $this->assertTrue($e->retryable); $this->assertSame(180,$e->retryAfterSeconds);
            $this->assertSame(429,$e->httpStatus);
            $this->assertStringNotContainsString('never log this',$e->getMessage());
        }
    }

    public function test_accepted_message_and_unregistered_error_are_not_confused_with_handset_delivery(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response(['name'=>'projects/synthetic/messages/test'],200)]);
        app(FcmPushSender::class)->send($notification,$device);
        Http::assertSentCount(1);
        $this->assertNotNull($device->fresh()->last_seen_at);
        $this->assertNull($device->fresh()->disabled_at);
    }

    public function test_external_envelope_contains_no_private_content_and_binds_recipient_and_registration(): void
    {
        [, $notification,$device]=$this->fixture();
        $notification->forceFill(['entity_type'=>'message_thread','entity_id'=>77,
            'data'=>['body'=>'PRIVATE_SENTINEL','recipient_id'=>'forged','route'=>'https://evil.test']])->save();
        Http::fake(['*'=>Http::response(['name'=>'accepted-not-delivered'],200)]);
        app(FcmPushSender::class)->send($notification,$device);
        Http::assertSent(function ($request) use ($notification,$device) {
            $message=$request['message'];
            $this->assertArrayNotHasKey('notification',$message);
            $this->assertArrayNotHasKey('notification',$message['android']);
            $this->assertSame(['notification_id'=>(string)$notification->id,
                'recipient_id'=>(string)$notification->user_id,'registration_hash'=>$device->token_hash,
                'route'=>'/messages/77'],$message['data']);
            $this->assertSame('com.aqer.yemen.uat',$message['android']['restricted_package_name']);
            $this->assertSame('300s',$message['android']['ttl']);
            $this->assertStringNotContainsString('PRIVATE_SENTINEL',json_encode($message));
            $this->assertStringNotContainsString($notification->title,json_encode($message));
            return true;
        });
    }

    public function test_queue_releases_throttle_for_provider_delay_and_stops_after_last_attempt(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response([],429,['Retry-After'=>'180'])]);
        $queue=\Mockery::mock(\Illuminate\Contracts\Queue\Job::class);
        $queue->shouldReceive('attempts')->andReturn(1);
        $queue->shouldReceive('release')->once()->with(180);
        $job=(new SendUserPushNotification($notification->id,$device->id))->setJob($queue);
        $job->handle(app(FcmPushSender::class));
        $final=\Mockery::mock(\Illuminate\Contracts\Queue\Job::class);
        $final->shouldReceive('attempts')->andReturn(3);
        $final->shouldNotReceive('release');
        $this->expectException(\App\Services\PushDeliveryException::class);
        (new SendUserPushNotification($notification->id,$device->id))->setJob($final)->handle(app(FcmPushSender::class));
    }

    public function test_permanent_provider_failure_is_marked_failed_without_retry_or_disabling_registration(): void
    {
        [, $notification,$device]=$this->fixture();
        Http::fake(['*'=>Http::response([],403)]);
        $queue=\Mockery::mock(\Illuminate\Contracts\Queue\Job::class);
        $queue->shouldReceive('fail')->once()->with(\Mockery::type(\App\Services\PushDeliveryException::class));
        $queue->shouldNotReceive('release');
        (new SendUserPushNotification($notification->id,$device->id))->setJob($queue)->handle(app(FcmPushSender::class));
        $this->assertNull($device->fresh()->disabled_at);
    }

    public function test_removed_registration_and_changed_account_never_receive_a_queued_message(): void
    {
        [, $notification,$device]=$this->fixture();
        $other=User::create(['name'=>'Other synthetic account','email'=>'other-push@example.test','password'=>'fixture-only','account_status'=>User::STATUS_ACTIVE]);
        $device->update(['user_id'=>$other->id]);
        Http::fake(['*'=>Http::response([],200)]);
        (new SendUserPushNotification($notification->id,$device->id))->handle(app(FcmPushSender::class));
        $device->delete();
        (new SendUserPushNotification($notification->id,$device->id))->handle(app(FcmPushSender::class));
        Http::assertNothingSent();
    }

    public function test_push_uses_separate_database_queue_even_when_web_default_is_sync(): void
    {
        $job=new SendUserPushNotification(1,2);
        $this->assertSame('database',$job->connection);
        $this->assertSame('push',$job->queue);
    }

    public function test_production_rejects_uat_identity_before_any_network_request(): void
    {
        [, $notification,$device]=$this->fixture();
        $this->app->instance('env','production');
        Http::fake();
        try { app(FcmPushSender::class)->send($notification,$device); $this->fail('UAT push must fail closed'); }
        catch (\RuntimeException $error) { $this->assertStringContainsString('forbidden in production',$error->getMessage()); }
        Http::assertNothingSent();
    }
}
