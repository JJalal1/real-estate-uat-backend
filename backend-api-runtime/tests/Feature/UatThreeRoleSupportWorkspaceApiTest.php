<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\SupportCase;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UatThreeRoleSupportWorkspaceApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_shared_support_queue_claim_is_atomic_and_manager_can_reassign(): void
    {
        [, $requesterHeaders] = $this->user('ws-requester@example.test', '+967733300001');
        [$agentA, $agentAHeaders] = $this->user('ws-agent-a@example.test', '+967733300002', ['support_agent']);
        [$agentB, $agentBHeaders] = $this->user('ws-agent-b@example.test', '+967733300003', ['support_agent']);
        [, $managerHeaders] = $this->user('ws-manager@example.test', '+967733300004', ['support_manager']);

        $caseId = (int) $this->withHeaders($requesterHeaders)->postJson('/api/support/cases', [
            'subject' => 'Workspace queue ticket',
            'description' => 'A support ticket that must be claimed from the shared queue.',
            'category' => 'technical',
        ])->assertCreated()->json('data.id');

        $firstQueue = $this->withHeaders($agentAHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=support_ticket')
            ->assertOk()
            ->assertJsonPath('meta.total', 1);
        $taskId = (int) $firstQueue->json('data.0.id');
        $this->assertSame($caseId, (int) $firstQueue->json('data.0.source_id'));
        $this->assertTrue((bool) $firstQueue->json('data.0.can_claim'));

        $this->withHeaders($agentBHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=support_ticket')
            ->assertOk()
            ->assertJsonPath('meta.total', 1);

        $this->withHeaders($agentAHeaders)
            ->postJson("/api/admin/workspace/tasks/$taskId/claim")
            ->assertOk()
            ->assertJsonPath('data.assigned_to_user_id', $agentA->id)
            ->assertJsonPath('data.status', 'in_progress');

        $this->withHeaders($agentBHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=support_ticket')
            ->assertOk()
            ->assertJsonPath('meta.total', 0);

        $this->withHeaders($agentBHeaders)
            ->postJson("/api/admin/workspace/tasks/$taskId/claim")
            ->assertStatus(409);

        $this->withHeaders($agentAHeaders)
            ->patchJson("/api/admin/workspace/tasks/$taskId/operational-status", ['status' => 'waiting_internal'])
            ->assertOk()
            ->assertJsonPath('data.status', 'waiting_internal');
        $this->assertDatabaseHas('support_cases', ['id' => $caseId, 'status' => 'in_progress']);

        $this->withHeaders($agentAHeaders)
            ->patchJson("/api/admin/workspace/tasks/$taskId/operational-status", ['status' => 'in_progress'])
            ->assertOk()
            ->assertJsonPath('data.status', 'in_progress');

        $this->withHeaders($agentAHeaders)
            ->getJson("/api/admin/workspace/tasks/$taskId/events")
            ->assertOk()
            ->assertJsonFragment(['event' => 'claimed'])
            ->assertJsonFragment(['event' => 'operational_status_changed']);

        $this->withHeaders($agentAHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=mine&type=support_ticket')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.is_mine', true);

        $this->withHeaders($managerHeaders)
            ->putJson("/api/admin/workspace/tasks/$taskId/assign", ['user_id' => $agentB->id])
            ->assertOk()
            ->assertJsonPath('data.assigned_to_user_id', $agentB->id);

        $this->assertDatabaseHas('support_tasks', [
            'id' => $taskId,
            'assigned_to_user_id' => $agentB->id,
            'status' => 'in_progress',
        ]);
        $this->assertDatabaseHas('support_cases', [
            'id' => $caseId,
            'assigned_to_user_id' => $agentB->id,
        ]);
        $this->assertDatabaseHas('support_task_events', [
            'support_task_id' => $taskId,
            'event' => 'claimed',
        ]);
        $this->assertDatabaseHas('support_task_events', [
            'support_task_id' => $taskId,
            'event' => 'assigned',
        ]);
    }

    public function test_support_agent_sees_agent_dashboard_and_manager_sees_team_dashboard(): void
    {
        [, $requesterHeaders] = $this->user('ws-dash-requester@example.test', '+967733300011');
        [, $agentHeaders] = $this->user('ws-dash-agent@example.test', '+967733300012', ['support_agent']);
        [, $managerHeaders] = $this->user('ws-dash-manager@example.test', '+967733300013', ['support_manager']);

        $this->withHeaders($requesterHeaders)->postJson('/api/support/cases', [
            'subject' => 'Dashboard ticket',
            'description' => 'Dashboard metric source.',
            'category' => 'other',
        ])->assertCreated();

        $this->withHeaders($agentHeaders)
            ->getJson('/api/admin/workspace/dashboard')
            ->assertOk()
            ->assertJsonPath('data.mode', 'agent')
            ->assertJsonPath('data.inbox_new', 1)
            ->assertJsonStructure(['data' => ['my_tasks', 'tickets', 'reports', 'waiting_user', 'overdue', 'attention']]);

        $this->withHeaders($managerHeaders)
            ->getJson('/api/admin/workspace/dashboard')
            ->assertOk()
            ->assertJsonPath('data.mode', 'manager')
            ->assertJsonStructure(['data' => [
                'unassigned', 'in_progress', 'overdue', 'waiting_user',
                'escalated', 'critical_reports', 'active_agents', 'average_claim_minutes',
                'average_response_minutes',
            ]]);

        $this->withHeaders($managerHeaders)
            ->getJson('/api/admin/workspace/team')
            ->assertOk()
            ->assertJsonStructure(['data' => [['id', 'name', 'role', 'open_tasks', 'closed_tasks', 'overdue_tasks', 'average_response_minutes']]]);
    }

    public function test_regular_user_cannot_open_administrative_workspace(): void
    {
        [, $headers] = $this->user('ws-regular@example.test', '+967733300021');

        $this->withHeaders($headers)
            ->getJson('/api/admin/workspace/dashboard')
            ->assertForbidden();
        $this->withHeaders($headers)
            ->getJson('/api/admin/workspace/tasks?scope=inbox')
            ->assertForbidden();
    }

    public function test_support_agent_cannot_bypass_verification_task_ownership_via_legacy_routes(): void
    {
        [$requester] = $this->user('ws-kyc-requester@example.test', '+967733300031');
        [$agentA, $agentAHeaders] = $this->user('ws-kyc-agent-a@example.test', '+967733300032', ['support_agent']);
        [, $agentBHeaders] = $this->user('ws-kyc-agent-b@example.test', '+967733300033', ['support_agent']);

        DB::table('account_verification_profiles')->insert([
            'user_id' => $requester->id,
            'type' => 'owner',
            'status' => 'pending',
            'details' => json_encode([], JSON_THROW_ON_ERROR),
            'submitted_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $queue = $this->withHeaders($agentAHeaders)
            ->getJson('/api/admin/workspace/tasks?scope=inbox&type=account_verification')
            ->assertOk()
            ->assertJsonPath('meta.total', 1);
        $taskId = (int) $queue->json('data.0.id');

        foreach (['approve', 'more-info', 'reject'] as $action) {
            $payload = $action === 'approve' ? [] : ['reason' => 'Ownership regression check'];
            $this->withHeaders($agentBHeaders)
                ->postJson("/api/admin/account-verifications/{$requester->id}/{$action}", $payload)
                ->assertStatus(409);
        }

        $this->withHeaders($agentAHeaders)
            ->postJson("/api/admin/workspace/tasks/{$taskId}/claim")
            ->assertOk()
            ->assertJsonPath('data.assigned_to_user_id', $agentA->id);

        $this->withHeaders($agentAHeaders)
            ->postJson("/api/admin/account-verifications/{$requester->id}/more-info", [
                'reason' => 'Please provide a clearer identity document.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'needs_more_info');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Workspace User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $ids = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $ids[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($ids);
        $plain = 'ws_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'support-workspace-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), [
            'Authorization' => 'Bearer ' . $plain,
            'Accept' => 'application/json',
        ]];
    }
}
