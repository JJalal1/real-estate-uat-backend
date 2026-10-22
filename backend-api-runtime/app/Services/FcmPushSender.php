<?php

namespace App\Services;

use App\Models\UserNotification;
use App\Models\UserPushDevice;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class FcmPushSender
{
    public function send(UserNotification $notification): void
    {
        if (! config('push.enabled',false)) return;
        if (config('push.provider','fcm') !== 'fcm') {
            throw new RuntimeException('Unsupported push provider.');
        }

        $devices=UserPushDevice::query()
            ->where('user_id',$notification->user_id)
            ->whereNull('disabled_at')
            ->orderBy('id')
            ->get();

        if ($devices->isEmpty()) return;

        $accessToken=$this->accessToken();
        $projectId=$this->projectId();
        $client=$this->client()->withToken($accessToken);

        foreach ($devices as $device) {
            $response=$client->post(
                'https://fcm.googleapis.com/v1/projects/'.rawurlencode($projectId).'/messages:send',
                ['message'=>$this->message($notification,(string)$device->token)],
            );

            if ($response->successful()) {
                $device->forceFill(['last_seen_at'=>now()])->save();
                continue;
            }

            $body=$response->body();
            if ($response->status()===404 || str_contains($body,'UNREGISTERED')) {
                $device->forceFill(['disabled_at'=>now()])->save();
                continue;
            }

            throw new RuntimeException(
                'FCM delivery failed with HTTP '.$response->status().'.',
            );
        }
    }

    private function message(UserNotification $notification,string $token): array
    {
        $data=[
            'notification_id'=>(string)$notification->id,
            'type'=>$notification->type,
        ];
        if ($notification->entity_type) $data['entity_type']=$notification->entity_type;
        if ($notification->entity_id) $data['entity_id']=(string)$notification->entity_id;
        foreach ((array)($notification->data ?? []) as $key=>$value) {
            if (! is_string($key) || array_key_exists($key,$data)) continue;
            $data[$key]=$this->stringValue($value);
        }

        return [
            'token'=>$token,
            'notification'=>array_filter([
                'title'=>$notification->title,
                'body'=>$notification->body,
            ],static fn($value)=>is_string($value) && $value!==''),
            'data'=>$data,
            'android'=>[
                'priority'=>'high',
                'notification'=>[
                    'channel_id'=>'aqer_general',
                    'sound'=>'default',
                ],
            ],
        ];
    }

    private function stringValue(mixed $value): string
    {
        if (is_string($value)) return $value;
        if (is_bool($value)) return $value ? 'true' : 'false';
        if (is_int($value) || is_float($value)) return (string)$value;
        if ($value===null) return '';
        return json_encode($value,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) ?: '';
    }

    private function accessToken(): string
    {
        $credentials=$this->credentials();
        $cacheKey='fcm-oauth-token:'.hash('sha256',(string)config('push.fcm.service_account_json_base64'));
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
        if ($encoded==='') throw new RuntimeException('FCM service account is not configured.');
        $decoded=base64_decode($encoded,true);
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
