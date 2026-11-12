<?php

namespace Tests\Feature;

use App\Models\ConversationReport;
use App\Models\MessageThread;
use App\Models\MessageThreadParticipant;
use App\Models\PrivateMessage;
use App\Models\Role;
use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase23InboxPaginationTest extends TestCase
{
    use RefreshDatabase;

    public function test_thread_pages_keep_latest_order_preview_unread_and_participant_scope(): void
    {
        [$viewer, $headers] = $this->user('viewer');
        [$other] = $this->user('other');
        [$outsider, $outsiderHeaders] = $this->user('outsider');
        $threads = [];
        foreach (range(1, 5) as $index) {
            $threads[] = $this->thread($viewer, $other, 'ordered-'.$index);
        }
        $foreign = $this->thread($outsider, $other, 'foreign');
        $this->message($foreign, $other, 'Foreign private preview');
        // All timestamps tie. The highest ID wins and is still visible when
        // personal messaging is blocked; paging must not rewrite that policy.
        $latest = $threads[4];
        $read = $this->message($latest, $other, 'Already read');
        $this->message($latest, $other, 'Unread incoming');
        $this->message($latest, $viewer, 'Latest outgoing preview');
        MessageThreadParticipant::query()->where('thread_id', $latest->id)
            ->where('user_id', $viewer->id)->update(['last_read_message_id' => $read->id]);
        MessageThreadParticipant::query()->where('thread_id', $latest->id)
            ->where('user_id', $other->id)->update(['last_read_message_id' => 999999]);
        DB::table('user_messaging_blocks')->insert([
            'user_id' => $viewer->id, 'blocked_user_id' => $other->id,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $expected = array_reverse(array_map(fn (MessageThread $thread): int => $thread->id, $threads));
        for ($attempt = 0; $attempt < 2; $attempt++) {
            $received = [];
            foreach (array_chunk($expected, 2) as $index => $ids) {
                $response = $this->withHeaders($headers)
                    ->getJson('/api/messages/threads?per_page=2&page='.($index + 1))
                    ->assertOk()->assertJsonPath('meta.current_page', $index + 1)
                    ->assertJsonPath('meta.last_page', 3)->assertJsonPath('meta.total', 5)
                    ->assertJsonPath('meta.per_page', 2);
                $actual = array_column($response->json('data'), 'id');
                $this->assertSame($ids, $actual);
                $this->assertSame([], array_values(array_intersect($received, $actual)));
                $received = array_merge($received, $actual);
                if ($index === 0) {
                    $response->assertJsonPath('data.0.last_message_preview', 'Latest outgoing preview')
                        ->assertJsonPath('data.0.unread_count', 1)
                        ->assertJsonPath('data.0.blocked_by_me', true)
                        ->assertJsonPath('data.0.can_send', false);
                }
            }
            $this->assertSame($expected, $received);
        }
        $this->withHeaders($headers)->getJson('/api/messages/threads?per_page=2&page=4')
            ->assertOk()->assertJsonCount(0, 'data')->assertJsonPath('meta.total', 5);
        $this->withHeaders($outsiderHeaders)->getJson('/api/messages/threads?per_page=1&page=1')
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.id', $foreign->id);
        $this->withHeaders($headers)->getJson('/api/messages/threads?per_page=1&unread_only=1')
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.id', $latest->id)
            ->assertJsonPath('data.0.unread_count', 1);
        $this->assertDatabaseHas('message_thread_participants', [
            'thread_id' => $latest->id, 'user_id' => $viewer->id, 'last_read_message_id' => $read->id,
        ]);
    }

    public function test_legacy_limit_is_preserved_and_unread_filter_reaches_a_thread_beyond_it(): void
    {
        [$viewer, $headers] = $this->user('large-viewer');
        [$other] = $this->user('large-other');
        $threads = [];
        $participants = [];
        foreach (range(1000, 1250) as $id) {
            $threads[] = [
                'id' => $id, 'started_by_user_id' => $viewer->id,
                'conversation_key' => 'broker:pagination:'.$id,
                'last_message_at' => '2026-01-01 12:00:00',
                'created_at' => '2026-01-01 12:00:00', 'updated_at' => '2026-01-01 12:00:00',
            ];
            foreach ([$viewer, $other] as $participant) {
                $participants[] = ['thread_id' => $id, 'user_id' => $participant->id,
                    'user_name_snapshot' => $participant->name];
            }
        }
        DB::table('message_threads')->insert($threads);
        foreach (array_chunk($participants, 200) as $chunk) {
            DB::table('message_thread_participants')->insert($chunk);
        }
        $oldest = MessageThread::query()->findOrFail(1000);
        $this->message($oldest, $other, 'Old but unread incoming message');
        // Self-authored messages and already-read incoming history must not
        // count as unread, regardless of the other participant's read marker.
        $newest = MessageThread::query()->findOrFail(1250);
        $this->message($newest, $viewer, 'My outgoing message');
        $readThread = MessageThread::query()->findOrFail(1249);
        $read = $this->message($readThread, $other, 'Read incoming message');
        MessageThreadParticipant::query()->where('thread_id', $readThread->id)
            ->where('user_id', $viewer->id)->update(['last_read_message_id' => $read->id]);
        $this->withHeaders($headers)->getJson('/api/messages/threads')->assertOk()
            ->assertJsonCount(250, 'data')->assertJsonPath('meta.per_page', 250)
            ->assertJsonPath('meta.total', 251)->assertJsonPath('meta.last_page', 2)
            ->assertJsonPath('data.0.id', 1250)->assertJsonPath('data.249.id', 1001);
        $this->withHeaders($headers)->getJson('/api/messages/threads?page=2')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', 1000);
        $this->withHeaders($headers)->getJson('/api/messages/threads?per_page=40&unread_only=1')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('meta.total', 1)
            ->assertJsonPath('meta.last_page', 1)->assertJsonPath('data.0.id', 1000)
            ->assertJsonPath('data.0.unread_count', 1);
        $this->withHeaders($headers)->getJson('/api/messages/threads?per_page=40&unread_only=0')
            ->assertOk()->assertJsonCount(40, 'data')->assertJsonPath('meta.total', 251);
    }

    public function test_notification_pages_preserve_unread_owner_and_retired_feature_filters(): void
    {
        [$viewer, $headers] = $this->user('notification-viewer');
        [$other, $otherHeaders] = $this->user('notification-other');
        $rows = [];
        foreach (range(1, 201) as $index) {
            $rows[] = ['user_id' => $viewer->id, 'type' => 'support_reply',
                'title' => 'Synthetic notification '.$index, 'created_at' => '2026-01-01 12:00:00'];
        }
        DB::table('user_notifications')->insert($rows);
        $ids = UserNotification::query()->where('user_id', $viewer->id)->latest('id')->pluck('id')->all();
        $foreign = $this->notification($other);
        $this->notification($viewer, ['read_at' => now()]);
        $this->notification($viewer, ['type' => 'booking_confirmed']);
        $this->notification($viewer, ['entity_type' => 'viewing_booking']);
        $this->withHeaders($headers)->getJson('/api/notifications')->assertOk()
            ->assertJsonCount(200, 'data')->assertJsonPath('meta.per_page', 200)
            ->assertJsonPath('meta.total', 201)->assertJsonPath('data.0.id', $ids[0]);
        $this->withHeaders($headers)->getJson('/api/notifications?page=2')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $ids[200]);
        $first = $this->withHeaders($headers)->getJson('/api/notifications?per_page=40&page=1')
            ->assertOk()->assertJsonPath('meta.last_page', 6)->json('data');
        $second = $this->withHeaders($headers)->getJson('/api/notifications?per_page=40&page=2')
            ->assertOk()->json('data');
        $this->assertSame(array_slice($ids, 0, 80), array_column(array_merge($first, $second), 'id'));
        $this->withHeaders($headers)->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count', 201);
        $this->withHeaders($otherHeaders)->getJson('/api/notifications?per_page=40')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $foreign->id);
        $this->withHeaders($headers)->postJson('/api/notifications/'.$foreign->id.'/read')->assertNotFound();
        $this->withHeaders($headers)->postJson('/api/notifications/'.$ids[0].'/read')->assertOk();
        // Offset pages represent current state: a read action requires a fresh
        // first page; it must not silently mark the remaining rows read.
        $this->withHeaders($headers)->getJson('/api/notifications?per_page=40&page=1')
            ->assertOk()->assertJsonPath('meta.total', 200)->assertJsonPath('data.0.id', $ids[1]);
        $this->withHeaders($headers)->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count', 200);
    }

    public function test_report_pages_keep_filter_and_permission_without_opening_private_content(): void
    {
        [$reporter, $regularHeaders] = $this->user('reporter');
        [$other] = $this->user('report-other');
        [, $agentHeaders] = $this->user('report-agent', ['support_agent']);
        $thread = $this->thread($reporter, $other, 'reported');
        $this->message($thread, $other, 'Private content must not enter the queue');
        $rows = [];
        foreach (range(1, 201) as $index) {
            // One active report is permitted per thread and reporter.
            $reportedThread = $index === 1 ? $thread : $this->thread($reporter, $other, 'reported-'.$index);
            $rows[] = ['thread_id' => $reportedThread->id, 'reporter_user_id' => $reporter->id,
                'reporter_name_snapshot' => $reporter->name, 'reason_code' => 'other',
                'details' => 'Synthetic private report details', 'status' => 'open',
                'created_at' => '2026-01-01 12:00:00', 'updated_at' => '2026-01-01 12:00:00'];
        }
        foreach (array_chunk($rows, 100) as $chunk) {
            DB::table('conversation_reports')->insert($chunk);
        }
        $ids = ConversationReport::query()->latest('id')->pluck('id')->all();
        ConversationReport::query()->create(array_replace($rows[0], ['status' => 'resolved']));
        $this->withHeaders($agentHeaders)->getJson('/api/admin/messages/reports?status=open')
            ->assertOk()->assertJsonCount(200, 'data')->assertJsonPath('meta.per_page', 200)
            ->assertJsonPath('meta.total', 201)->assertJsonPath('data.0.id', $ids[0]);
        $this->withHeaders($agentHeaders)->getJson('/api/admin/messages/reports?status=open&page=2')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $ids[200]);
        $received = [];
        foreach ([1, 2] as $page) {
            $data = $this->withHeaders($agentHeaders)
                ->getJson('/api/admin/messages/reports?status=open&per_page=40&page='.$page)
                ->assertOk()->assertJsonPath('meta.last_page', 6)->json('data');
            foreach ($data as $report) {
                $this->assertArrayNotHasKey('messages', $report);
                $this->assertArrayNotHasKey('details', $report);
                $this->assertSame('open', $report['status']);
            }
            $received = array_merge($received, array_column($data, 'id'));
            $this->withHeaders($regularHeaders)->getJson('/api/admin/messages/reports?per_page=40&page='.$page)
                ->assertForbidden();
        }
        $this->assertSame(array_slice($ids, 0, 80), $received);
        $this->withHeaders($agentHeaders)->getJson('/api/admin/messages/reports?status=resolved&per_page=40')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('meta.total', 1);
        $this->withHeaders($agentHeaders)->getJson('/api/admin/messages/reports/'.$ids[0].'/content')->assertForbidden();
        $this->assertDatabaseCount('private_message_access_events', 0);
    }

    public function test_pagination_is_bounded_and_rejects_malformed_queries(): void
    {
        [, $headers] = $this->user('validation-agent', ['support_agent']);
        foreach (['/api/messages/threads' => 250, '/api/notifications' => 200, '/api/admin/messages/reports' => 200] as $url => $limit) {
            foreach (['page=0' => 'page', 'page=abc' => 'page', 'page[]=1' => 'page',
                'per_page=0' => 'per_page', 'per_page='.($limit + 1) => 'per_page',
                'per_page=1.5' => 'per_page'] as $query => $field) {
                $this->withHeaders($headers)->getJson($url.'?'.$query)
                    ->assertUnprocessable()->assertJsonValidationErrors($field);
            }
            $this->withHeaders($headers)->getJson($url.'?page=1&per_page=1')
                ->assertOk()->assertJsonCount(0, 'data')->assertJsonPath('meta.total', 0)
                ->assertJsonPath('meta.current_page', 1)->assertJsonPath('meta.last_page', 1);
        }
        $this->withHeaders($headers)->getJson('/api/messages/threads?unread_only=invalid')
            ->assertUnprocessable()->assertJsonValidationErrors('unread_only');
        $this->withHeaders($headers)->getJson('/api/admin/messages/reports?status=invalid')
            ->assertUnprocessable()->assertJsonValidationErrors('status');
    }

    public function test_guest_and_inactive_accounts_cannot_read_any_inbox_page(): void
    {
        $urls = ['/api/messages/threads', '/api/notifications', '/api/admin/messages/reports'];
        foreach ($urls as $url) {
            $this->getJson($url.'?page=2&per_page=40')->assertUnauthorized();
        }
        [$inactive, $headers] = $this->user('inactive-agent', ['support_agent']);
        $inactive->forceFill(['account_status' => User::STATUS_SUSPENDED])->save();
        foreach ($urls as $url) {
            $this->withHeaders($headers)->getJson($url.'?page=2&per_page=40')->assertForbidden();
        }
    }

    private function thread(User $viewer, User $other, string $key): MessageThread
    {
        $thread = MessageThread::query()->create([
            'started_by_user_id' => $viewer->id, 'conversation_key' => 'broker:pagination:'.$key,
            'last_message_at' => '2026-01-01 12:00:00',
        ]);
        foreach ([$viewer, $other] as $user) {
            $thread->participants()->create(['user_id' => $user->id, 'user_name_snapshot' => $user->name]);
        }
        return $thread;
    }

    private function message(MessageThread $thread, User $sender, string $body): PrivateMessage
    {
        return $thread->messages()->create(['sender_user_id' => $sender->id,
            'sender_name_snapshot' => $sender->name, 'body' => $body, 'created_at' => '2026-01-01 12:00:00']);
    }

    private function notification(User $user, array $attributes = []): UserNotification
    {
        return UserNotification::query()->create(array_replace([
            'user_id' => $user->id, 'type' => 'support_reply', 'title' => 'Synthetic notification',
            'created_at' => '2026-01-01 12:00:00',
        ], $attributes));
    }

    private function user(string $key, array $roles = []): array
    {
        $user = User::query()->create(['name' => 'Synthetic inbox '.$key,
            'email' => $key.'@example.test', 'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE, 'password' => Hash::make('SyntheticInboxPassword!')]);
        $sync = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $sync[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($sync);
        $token = 'inbox_'.substr(hash('sha512', $user->email), 0, 80);
        $user->apiTokens()->create(['name' => 'inbox-pagination-test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }
}
