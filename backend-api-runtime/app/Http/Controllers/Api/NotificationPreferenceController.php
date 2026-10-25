<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserNotificationPreference;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class NotificationPreferenceController extends Controller
{
    private const FIELDS = [
        'messages',
        'viewings',
        'agreements',
        'listing_activity',
        'discovery_alerts',
        'services',
    ];

    public function show(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $row = DB::transaction(fn () => $this->activePreference($user), 3);

        return response()->json(['data' => $this->data($row)]);
    }

    public function update(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $rules = [];
        foreach (self::FIELDS as $field) {
            $rules[$field] = ['sometimes', 'boolean'];
        }
        $validated = $request->validate($rules);

        $row = DB::transaction(function () use ($user, $validated): UserNotificationPreference {
            $row = $this->activePreference($user);
            if ($validated !== []) $row->fill($validated)->save();
            return $row;
        }, 3);

        return response()->json([
            'message' => 'تم تحديث تفضيلات الإشعارات.',
            'data' => $this->data($row),
        ]);
    }

    private function activePreference(User $actor): UserNotificationPreference
    {
        // GET may create defaults too. Coordinate both paths with erasure,
        // and recheck activity after the HTTP middleware snapshot.
        $current = User::query()->whereKey($actor->id)->lockForUpdate()->firstOrFail();
        abort_unless($current->isActive(), 403, 'هذا الحساب غير متاح حاليًا.');
        return UserNotificationPreference::query()->firstOrCreate(
            ['user_id' => $current->id], $this->defaults(),
        );
    }

    private function defaults(): array
    {
        return array_fill_keys(self::FIELDS, true);
    }

    private function data(UserNotificationPreference $row): array
    {
        return [
            'messages' => (bool) $row->messages,
            'viewings' => (bool) $row->viewings,
            'agreements' => (bool) $row->agreements,
            'listing_activity' => (bool) $row->listing_activity,
            'discovery_alerts' => (bool) $row->discovery_alerts,
            'services' => (bool) $row->services,
            'essential_always_on' => true,
        ];
    }
}
