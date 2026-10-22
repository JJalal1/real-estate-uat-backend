<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserPushDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PushDeviceController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $v=$request->validate([
            'platform'=>['required','string','in:android'],
            'token'=>['required','string','min:20','max:4096'],
            'installation_id'=>['required','string','min:16','max:200'],
            'app_build'=>['nullable','integer','min:1','max:2147483647'],
        ]);

        $user=$request->user();
        $token=trim((string)$v['token']);
        $tokenHash=hash('sha256',$token);
        $installationHash=hash('sha256',trim((string)$v['installation_id']));

        $device=DB::transaction(function () use ($user,$v,$token,$tokenHash,$installationHash) {
            UserPushDevice::query()
                ->where('token_hash',$tokenHash)
                ->where('user_id','<>',$user->id)
                ->delete();

            return UserPushDevice::query()->updateOrCreate(
                [
                    'user_id'=>$user->id,
                    'installation_hash'=>$installationHash,
                ],
                [
                    'platform'=>$v['platform'],
                    'token'=>$token,
                    'token_hash'=>$tokenHash,
                    'app_build'=>$v['app_build'] ?? null,
                    'last_seen_at'=>now(),
                    'disabled_at'=>null,
                ],
            );
        });

        return response()->json([
            'data'=>[
                'registered'=>true,
                'device_id'=>$device->id,
                'push_enabled'=>(bool)config('push.enabled',false),
            ],
        ]);
    }

    public function destroy(Request $request): JsonResponse
    {
        $v=$request->validate([
            'installation_id'=>['required','string','min:16','max:200'],
        ]);
        $hash=hash('sha256',trim((string)$v['installation_id']));
        $deleted=UserPushDevice::query()
            ->where('user_id',$request->user()->id)
            ->where('installation_hash',$hash)
            ->delete();

        return response()->json(['data'=>['removed'=>$deleted>0]]);
    }
}
