<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase23PrivateQueuePaginationTest extends TestCase
{
    use RefreshDatabase;

    public function test_support_pages_use_id_after_priority_sla_and_creation_time_without_widening_scope(): void
    {
        [$agent, $headers] = $this->user('queue-agent@example.test', '+967744430001', ['support_agent']);
        [$otherAgent] = $this->user('queue-other@example.test', '+967744430002', ['support_agent']);
        $teamId = $this->putAgentInFallback($agent);

        // Insert equal-key rows out of ID order; the tie crosses the page boundary.
        foreach ([103, 101, 104, 102] as $id) {
            $this->task($id, $teamId);
        }
        $this->task(900, $teamId, ['priority' => 'urgent', 'sla_due_at' => '2026-02-10 12:00:00']);
        $this->task(800, $teamId, ['sla_due_at' => '2026-02-01 11:00:00']);
        $this->task(700, $teamId, ['created_at' => '2026-01-01 11:00:00']);
        $this->task(50, $teamId, ['sla_due_at' => null, 'created_at' => '2025-01-01 12:00:00']);

        $this->task(1, $teamId, ['assigned_to_user_id' => $otherAgent->id]);
        $this->task(2, $teamId, ['status' => 'completed']);
        $this->task(3, $teamId, ['support_team_id' => null]);

        $this->assertStableTwoPages(
            '/api/admin/workspace/tasks?scope=inbox&per_page=4',
            $headers,
            [[900, 800, 700, 101], [102, 103, 104, 50]],
        );
    }

    public function test_listing_pages_use_id_after_review_status_and_submission_time_without_revealing_other_claims(): void
    {
        [$reviewer, $headers] = $this->user('queue-reviewer@example.test', '+967744430003', ['support_agent']);
        [$otherReviewer] = $this->user('queue-other-reviewer@example.test', '+967744430004', ['support_agent']);
        [$advertiser] = $this->user('queue-advertiser@example.test', '+967744430005');

        foreach ([2103, 2101, 2104, 2102] as $id) {
            $this->listing($id, $advertiser);
        }
        $this->listing(2200, $advertiser, ['submitted_at' => '2026-01-01 11:00:00']);
        $this->listing(2000, $advertiser, [
            'review_status' => 'under_review',
            'review_assigned_to_user_id' => $reviewer->id,
            'submitted_at' => '2025-01-01 12:00:00',
        ]);
        $this->listing(3000, $advertiser, [
            'review_status' => 'under_review',
            'review_assigned_to_user_id' => $otherReviewer->id,
        ]);
        $this->listing(3001, $advertiser, ['review_assigned_to_user_id' => $otherReviewer->id]);
        $this->listing(3002, $advertiser, ['status' => 'draft', 'review_status' => 'draft']);

        $this->assertStableTwoPages(
            '/api/admin/listing-review/queue?per_page=3',
            $headers,
            [[2200, 2101, 2102], [2103, 2104, 2000]],
        );
        $this->withHeaders($headers)
            ->getJson('/api/admin/listing-review/queue?review_status=under_review&per_page=2')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', 2000);
    }

    public function test_regular_account_cannot_read_either_private_queue_page(): void
    {
        [, $headers] = $this->user('queue-regular@example.test', '+967744430006');

        foreach ([1, 2] as $page) {
            $this->withHeaders($headers)
                ->getJson('/api/admin/workspace/tasks?scope=inbox&per_page=2&page='.$page)
                ->assertForbidden();
            $this->withHeaders($headers)
                ->getJson('/api/admin/listing-review/queue?per_page=2&page='.$page)
                ->assertForbidden();
        }
    }

    private function assertStableTwoPages(string $url, array $headers, array $expectedPages): void
    {
        $expected = array_merge(...$expectedPages);
        for ($attempt = 0; $attempt < 2; $attempt++) {
            $received = [];
            foreach ($expectedPages as $index => $expectedIds) {
                $response = $this->withHeaders($headers)->getJson($url.'&page='.($index + 1))
                    ->assertOk()
                    ->assertJsonPath('meta.current_page', $index + 1)
                    ->assertJsonPath('meta.last_page', 2)
                    ->assertJsonPath('meta.total', count($expected))
                    ->assertJsonCount(count($expectedIds), 'data');
                $ids = array_column($response->json('data'), 'id');
                $this->assertSame($expectedIds, $ids);
                $this->assertSame([], array_values(array_intersect($received, $ids)));
                $received = array_merge($received, $ids);
            }
            $this->assertSame($expected, $received);
        }
    }

    private function task(int $id, int $teamId, array $attributes = []): void
    {
        SupportTask::forceCreate(array_replace([
            'id' => $id,
            'source_type' => 'account_verification',
            'source_id' => $id,
            'subject' => 'Synthetic pagination task '.$id,
            'status' => 'new',
            'priority' => 'normal',
            'support_team_id' => $teamId,
            'sla_due_at' => '2026-02-01 12:00:00',
            'created_at' => '2026-01-01 12:00:00',
            'updated_at' => '2026-01-01 12:00:00',
        ], $attributes));
    }

    private function listing(int $id, User $advertiser, array $attributes = []): void
    {
        Property::forceCreate(array_replace([
            'id' => $id,
            'user_id' => $advertiser->id,
            'title' => 'Synthetic review listing '.$id,
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 50000000,
            'currency' => 'YER',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'pending',
            'review_status' => 'submitted',
            'submitted_at' => '2026-01-01 12:00:00',
            'created_at' => '2026-01-01 12:00:00',
            'updated_at' => '2026-01-01 12:00:00',
        ], $attributes));
    }

    private function putAgentInFallback(User $agent): int
    {
        $teamId = (int) DB::table('support_teams')->where('is_fallback', true)->value('id');
        DB::table('support_team_members')->updateOrInsert(
            ['support_team_id' => $teamId, 'user_id' => $agent->id],
            ['member_role' => 'agent', 'is_available' => true, 'capacity' => 10, 'joined_at' => now(), 'created_at' => now(), 'updated_at' => now()],
        );
        return $teamId;
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Queue Pagination User', 'email' => $email, 'phone' => $phone, 'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE, 'password' => Hash::make('SyntheticQueueTestPassword!'),
        ]);
        $roleIds = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $roleIds[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($roleIds);
        $token = 'queue_'.substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'queue-pagination-test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }
}
