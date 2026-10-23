<?php
namespace App\Services;

use App\Models\Property;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class LegacyOwnershipService
{
    private const STAGE5_DEMO_EMAIL = 'stage5-owner@local.invalid';

    public function claim(User $user, ?string $ownerKey): int
    {
        $ownerKey = trim((string)$ownerKey);
        if ($ownerKey === '') return 0;
        if (strlen($ownerKey) < 32 || strlen($ownerKey) > 96) {
            throw ValidationException::withMessages(['legacy_owner_key'=>['Invalid legacy owner key.']]);
        }

        $demoUserId = User::query()->where('email',self::STAGE5_DEMO_EMAIL)->value('id');
        if (! $demoUserId) return 0;

        return DB::transaction(function () use ($user,$ownerKey,$demoUserId) {
            $ids = Property::query()
                ->where('owner_key',$ownerKey)->where('user_id',$demoUserId)
                ->lockForUpdate()->pluck('id');
            if ($ids->isEmpty()) return 0;
            return Property::query()->whereIn('id',$ids)->update([
                'user_id'=>$user->id,'owner_key'=>null,
            ]);
        });
    }
}
