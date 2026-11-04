<?php

namespace App\Services;

use App\Models\UserNotification;
use App\Models\UserPushDevice;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

class FcmPushSender
{
    public function validateConfiguration(): void
    {
        $this->androidPackage();
        $credentials=$this->credentials();
        if (! str_ends_with($credentials['client_email'],'.iam.gserviceaccount.com') ||
            ! @openssl_pkey_get_private($credentials['private_key'])) {
            throw new RuntimeException('FCM service account is not a valid server signing identity.');
        }
    }

    public function send(UserNotification $notification, UserPushDevice $device): void
    {
        if (! config('push.enabled',false)) return;
        if (config('push.provider','fcm') !== 'fcm') {
            throw new RuntimeException('Unsupported push provider.');
        }
        $this->androidPackage();
        if ((int)$device->user_id !== (int)$notification->user_id || $device->disabled_at) {
            return;
        }
        if (! app(UserNotificationService::class)->mayDeliver($notification)) return;

        $accessToken=$this->accessToken();
        // OAuth may take time. Do not send through a registration revoked or
        // transferred while it was obtained, nor through revoked preferences.
        $registration=fn () => UserPushDevice::query()->whereKey($device->id)
            ->where('user_id',$notification->user_id)->where('token_hash',$device->token_hash)->whereNull('disabled_at');
        if (! $registration()->exists() || ! app(UserNotificationService::class)->mayDeliver($notification)) return;

        $response=$this->client()
            ->withToken($accessToken)
            ->post(
                'https://fcm.googleapis.com/v1/projects/'.rawurlencode($this->projectId()).'/messages:send',
                ['message'=>$this->message($notification,(string)$device->token)],
            );

        if ($response->successful()) {
            $registration()->update(['last_seen_at'=>now()]);
            Log::info('push.provider_accepted',['notification_id'=>$notification->id,'device_id'=>$device->id]);
            return;
        }

        $details=$response->json('error.details',[]);
        $unregistered=is_array($details) && collect($details)->contains(fn ($detail) => is_array($detail) &&
            ($detail['@type'] ?? null)==='type.googleapis.com/google.firebase.fcm.v1.FcmError' && ($detail['errorCode'] ?? null)==='UNREGISTERED');
        if ($response->status()===404 && $unregistered) {
            $registration()->update(['disabled_at'=>now()]);
            Log::info('push.registration_expired',['notification_id'=>$notification->id,'device_id'=>$device->id]);
            return;
        }

        if ($response->status()===401) Cache::store('file')->forget($this->cacheKey());
        $retryable=$response->status()===429 || $response->serverError();
        $delay=60;
        $raw=trim((string)$response->header('Retry-After'));
        if (ctype_digit($raw)) $delay=(int)$raw;
        elseif ($raw!=='') { $timestamp=strtotime($raw); if ($timestamp!==false) $delay=$timestamp-time(); }
        Log::warning('push.provider_rejected',['notification_id'=>$notification->id,'device_id'=>$device->id,
            'http_status'=>$response->status(),'retryable'=>$retryable]);
        throw new PushDeliveryException($response->status(),$retryable,max(60,min(3600,$delay)));
    }

    private function message(UserNotification $notification,string $token): array
    {
        // A notification payload is rendered by Android before our account
        // checks when the app is backgrounded. Send an allowlisted data-only
        // envelope; private content is fetched through the authenticated API.
        return [
            'token'=>$token,
            'data'=>[
                'notification_id'=>(string)$notification->id,
                'recipient_id'=>(string)$notification->user_id,
                'registration_hash'=>hash('sha256',$token),
                'route'=>$this->routeFor($notification),
            ],
            'android'=>['priority'=>'high','ttl'=>'300s','restricted_package_name'=>$this->androidPackage()],
        ];
    }

    private function routeFor(UserNotification $notification): string
    {
        $id=(int)($notification->entity_id ?? 0);
        if ($id>0 && in_array($notification->entity_type,['property','listing'],true)) {
            return '/properties/'.$id;
        }
        if ($id>0 && in_array($notification->entity_type,['message_thread','conversation'],true)) {
            return '/messages/'.$id;
        }
        return '/notifications';
    }

    private function accessToken(): string
    {
        $credentials=$this->credentials();
        $cacheKey=$this->cacheKey($credentials);
        $cached=Cache::store('file')->get($cacheKey);
        if (is_string($cached) && $cached!=='') return $cached;

        $now=time();
        $header=$this->base64Url(json_encode(['alg'=>'RS256','typ'=>'JWT'],JSON_THROW_ON_ERROR));
        $claims=$this->base64Url(json_encode([
            'iss'=>$credentials['client_email'],
            'scope'=>'https://www.googleapis.com/auth/firebase.messaging',
            'aud'=>'https://oauth2.googleapis.com/token',
            'iat'=>$now,
            'exp'=>$now+3600,
        ],JSON_THROW_ON_ERROR));
        $unsigned=$header.'.'.$claims;
        $signature='';
        if (! openssl_sign($unsigned,$signature,$credentials['private_key'],OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('Unable to sign FCM OAuth assertion.');
        }
        $assertion=$unsigned.'.'.$this->base64Url($signature);

        $response=$this->client()->asForm()->post('https://oauth2.googleapis.com/token',[
            'grant_type'=>'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'=>$assertion,
        ]);
        if (! $response->successful()) {
            throw new RuntimeException('Unable to obtain FCM OAuth token.');
        }
        $token=(string)$response->json('access_token','');
        $expires=max(60,(int)$response->json('expires_in',3600)-120);
        if ($token==='') throw new RuntimeException('FCM OAuth response did not contain an access token.');
        Cache::store('file')->put($cacheKey,$token,$expires);

        return $token;
    }

    private function credentials(): array
    {
        $encoded=trim((string)config('push.fcm.service_account_json_base64',''));
        $file=trim((string)config('push.fcm.service_account_file',''));
        if ($file!=='' && $encoded!=='') throw new RuntimeException('Configure one FCM credential source.');
        if ($file==='') {
            if ($encoded==='' || strlen($encoded)>90000) throw new RuntimeException('FCM service account is not configured.');
            $decoded=base64_decode($encoded,true);
        } else {
            if (! is_file($file) || ! is_readable($file) || filesize($file)>65536) throw new RuntimeException('FCM secret file is unavailable.');
            $decoded=@file_get_contents($file,false,null,0,65537);
        }
        if (! is_string($decoded) || strlen($decoded)>65536) throw new RuntimeException('Invalid FCM service account JSON.');
        $json=is_string($decoded) ? json_decode($decoded,true) : null;
        if (! is_array($json)) throw new RuntimeException('Invalid FCM service account JSON.');
        foreach (['client_email','private_key','project_id'] as $key) {
            if (! is_string($json[$key] ?? null) || trim($json[$key])==='') {
                throw new RuntimeException('Incomplete FCM service account configuration.');
            }
        }
        $configured=$this->projectId();
        if (! hash_equals($configured,(string)$json['project_id'])) {
            throw new RuntimeException('FCM project mismatch.');
        }
        return $json;
    }

    private function cacheKey(?array $credentials=null): string
    {
        $file=trim((string)config('push.fcm.service_account_file',''));
        if ($file!=='') {
            // Hashing credentials also validates availability and project identity;
            // rotation cannot reuse an OAuth token from the previous secret file.
            return 'fcm-oauth-token:'.hash('sha256',json_encode($credentials ?? $this->credentials(),JSON_THROW_ON_ERROR));
        }
        return 'fcm-oauth-token:'.hash('sha256',(string)config('push.fcm.service_account_json_base64'));
    }

    private function androidPackage(): string
    {
        $package=trim((string)config('push.fcm.android_package',''));
        if (! preg_match('/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*){2,}$/D',$package) || $package==='com.example.real_estate_mobile') {
            throw new RuntimeException('Approved FCM Android package is not configured.');
        }
        if (! app()->environment(['staging','testing']) && ($package==='com.aqer.yemen.uat' || $this->projectId()==='aqer-yemen')) {
            throw new RuntimeException('UAT Firebase identity is forbidden in production.');
        }
        return $package;
    }

    private function projectId(): string
    {
        $value=trim((string)config('push.fcm.project_id',''));
        if ($value==='') throw new RuntimeException('FCM project id is not configured.');
        return $value;
    }

    private function client(): PendingRequest
    {
        return Http::connectTimeout(max(1,(int)config('push.fcm.connect_timeout_seconds',5)))
            ->timeout(max(2,(int)config('push.fcm.timeout_seconds',10)))
            ->acceptJson();
    }

    private function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value),'+/','-_'),'=');
    }
}
