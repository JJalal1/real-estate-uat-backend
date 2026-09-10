<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatGeneralManagerInsightsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_gets_executive_insights(): void
    {
        [, $headers] = $this->user('gm-owner@example.test', '+967733301001', ['super_admin']);

        $this->withHeaders($headers)
            ->getJson('/api/admin/workspace/general-manager/insights')
            ->assertOk()
            ->assertJsonPath('data.mode', 'general_manager')
            ->assertJsonStructure(['data' => [
                'overview' => [
                    'users_total', 'users_new_today', 'open_support_tasks',
                    'overdue_support_tasks', 'escalated_support_tasks',
                    'critical_reports', 'pending_listing_reviews', 'pending_verifications',
                ],
                'market' => [
                    'properties_total', 'published_properties', 'published_sale',
                    'published_rent', 'published_today', 'by_type', 'by_governorate',
                    'approved_brokers', 'approved_offices', 'pending_professional_verifications',
                ],
                'journey', 'team' => ['support_agents', 'support_managers'], 'today',
            ]]);
    }

    public function test_support_manager_and_agent_cannot_open_general_manager_insights(): void
    {
        [, $managerHeaders] = $this->user('gm-support-manager@example.test', '+967733301002', ['support_manager']);
        [, $agentHeaders] = $this->user('gm-support-agent@example.test', '+967733301003', ['support_agent']);
        [, $regularHeaders] = $this->user('gm-regular@example.test', '+967733301004');

        $this->withHeaders($managerHeaders)
            ->getJson('/api/admin/workspace/general-manager/insights')
            ->assertForbidden();
        $this->withHeaders($agentHeaders)
            ->getJson('/api/admin/workspace/general-manager/insights')
            ->assertForbidden();
        $this->withHeaders($regularHeaders)
            ->getJson('/api/admin/workspace/general-manager/insights')
            ->assertForbidden();
    }

    public function test_existing_support_dashboards_keep_their_roles(): void
    {
        [, $managerHeaders] = $this->user('gm-manager-regression@example.test', '+967733301005', ['support_manager']);
        [, $agentHeaders] = $this->user('gm-agent-regression@example.test', '+967733301006', ['support_agent']);

        $this->withHeaders($managerHeaders)
            ->getJson('/api/admin/workspace/dashboard')
            ->assertOk()
            ->assertJsonPath('data.mode', 'manager');

        $this->withHeaders($agentHeaders)
            ->getJson('/api/admin/workspace/dashboard')
            ->assertOk()
            ->assertJsonPath('data.mode', 'agent');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'UAT General Manager Test',
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

        $plain = 'gm_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'general-manager-insights-test',
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
