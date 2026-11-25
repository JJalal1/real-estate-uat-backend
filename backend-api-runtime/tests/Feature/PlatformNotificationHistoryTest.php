<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use App\Models\UserNotification;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PlatformNotificationHistoryTest extends TestCase
{
    use RefreshDatabase;

    public function test_history_and_unread_count_use_the_same_inclusive_window_across_pages(): void
    {
        $now = CarbonImmutable::parse('2026-11-26 12:34:56 UTC');
        $this->travelTo($now);
        [$owner, $headers] = $this->user('history-owner', '+967730000031');
        [$other] = $this->user('history-other', '+967730000032');

        $latestRead = $this->notification($owner, $now->subHour(), readAt: $now->subMinutes(5));
        $sameDateFirst = $this->notification($owner, $now->subDay());
        $boundary = $this->notification($owner, $now->subDays(7));
        $sameDateSecond = $this->notification($owner, $now->subDay());
        $older = $this->notification($owner, $now->subDays(7)->subSecond());
        $chat = $this->notification($owner, $now, type: 'message_received');
        $this->notification($other, $now);

        $this->getJson('/api/notifications?platform_history=1')->assertUnauthorized();

        $first = $this->withHeaders($headers)
            ->getJson('/api/notifications?platform_history=1&per_page=2')
            ->assertOk()->assertJsonPath('meta', [
                'current_page' => 1, 'last_page' => 2, 'per_page' => 2,
                'total' => 4, 'unread_count' => 3,
            ])->assertJsonPath('data.0.read_at', $latestRead->read_at->toIso8601String());
        $this->assertSame([$latestRead->id, $sameDateSecond->id], array_column($first->json('data'), 'id'));

        $second = $this->getJson('/api/notifications?platform_history=1&per_page=2&page=2')
            ->assertOk()->assertJsonPath('meta.unread_count', 3);
        $this->assertSame([$sameDateFirst->id, $boundary->id], array_column($second->json('data'), 'id'));

        $unread = $this->getJson('/api/notifications?platform_history=1&unread_only=1')->assertOk()
            ->assertJsonPath('meta.total', 3)->assertJsonPath('meta.unread_count', 3);
        $this->assertSame([$sameDateSecond->id, $sameDateFirst->id, $boundary->id], array_column($unread->json('data'), 'id'));
        $this->getJson('/api/notifications/unread-count?platform_history=1')->assertOk()
            ->assertExactJson(['data' => ['count' => 3]]);

        $legacy = $this->getJson('/api/notifications')->assertOk()->assertJsonPath('meta', [
            'current_page' => 1, 'last_page' => 1, 'per_page' => 200, 'total' => 5,
        ]);
        $this->assertSame([$chat->id, $older->id, $sameDateSecond->id, $boundary->id, $sameDateFirst->id], array_column($legacy->json('data'), 'id'));
        $this->getJson('/api/notifications/unread-count')->assertOk()
            ->assertExactJson(['data' => ['count' => 5]]);

        $this->travelTo($now->addSecond());
        $this->getJson('/api/notifications/unread-count?platform_history=1')->assertOk()
            ->assertJsonPath('data.count', 2);
        $this->getJson('/api/notifications?platform_history=1')->assertOk()
            ->assertJsonPath('meta.total', 3)->assertJsonPath('meta.unread_count', 2);
        $this->assertDatabaseHas('user_notifications', ['id' => $boundary->id, 'read_at' => null]);
    }

    public function test_platform_reads_retain_history_and_bulk_read_cannot_change_other_rows(): void
    {
        $now = CarbonImmutable::parse('2026-11-26 12:34:56 UTC');
        $this->travelTo($now);
        [$owner, $headers] = $this->user('history-reader', '+967730000033');
        [$other] = $this->user('history-outsider', '+967730000034');

        $first = $this->notification($owner, $now);
        $second = $this->notification($owner, $now->subDays(7));
        $old = $this->notification($owner, $now->subDays(7)->subSecond());
        $chat = $this->notification($owner, $now, type: 'message_received');
        $foreign = $this->notification($other, $now);

        $this->postJson('/api/notifications/history/read-all')->assertUnauthorized();
        $this->withHeaders($headers)->postJson('/api/notifications/'.$foreign->id.'/read')->assertNotFound();
        $this->postJson('/api/notifications/'.$first->id.'/read')->assertOk()
            ->assertJsonPath('data.read_at', $now->toIso8601String());
        $this->getJson('/api/notifications?platform_history=1')->assertOk()
            ->assertJsonPath('data.0.id', $first->id)
            ->assertJsonPath('meta.total', 2)->assertJsonPath('meta.unread_count', 1);
        $this->getJson('/api/notifications?platform_history=1&unread_only=1')->assertOk()
            ->assertJsonPath('data.0.id', $second->id)->assertJsonPath('meta.total', 1);

        $this->postJson('/api/notifications/history/read-all')->assertOk()->assertJsonPath('data.updated', 1);
        $this->postJson('/api/notifications/history/read-all')->assertOk()->assertJsonPath('data.updated', 0);
        $this->getJson('/api/notifications?platform_history=1')->assertOk()
            ->assertJsonPath('meta.total', 2)->assertJsonPath('meta.unread_count', 0)
            ->assertJsonPath('data.0.read_at', $now->toIso8601String())
            ->assertJsonPath('data.1.read_at', $now->toIso8601String());
        $this->getJson('/api/notifications?platform_history=1&unread_only=1')->assertOk()
            ->assertJsonPath('data', [])->assertJsonPath('meta.unread_count', 0);
        foreach ([$old, $chat, $foreign] as $untouched) {
            $this->assertDatabaseHas('user_notifications', ['id' => $untouched->id, 'read_at' => null]);
        }
        $this->assertDatabaseCount('user_notifications', 5);

        $this->postJson('/api/notifications/read-all')->assertOk()->assertExactJson([
            'message' => 'Notifications marked read.', 'data' => ['updated' => 2],
        ]);
        $this->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count', 0);
        $this->assertDatabaseHas('user_notifications', ['id' => $foreign->id, 'read_at' => null]);
    }

    private function notification(User $user, CarbonInterface $createdAt, string $type = 'support_reply', ?CarbonInterface $readAt = null): UserNotification
    {
        return UserNotification::query()->create([
            'user_id' => $user->id,
            'type' => $type,
            'title' => 'Notification history fixture',
            'created_at' => $createdAt,
            'read_at' => $readAt,
        ]);
    }

    private function user(string $name, string $phone): array
    {
        $user = User::query()->create([
            'name' => $name,
            'email' => $name.'@example.test',
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $role = Role::query()->where('key', 'registered_user')->firstOrFail();
        $user->roles()->sync([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
        $plain = 'notify_'.substr(hash('sha512', $name), 0, 72);
        $user->apiTokens()->create([
            'name' => 'notification-history-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }
}
