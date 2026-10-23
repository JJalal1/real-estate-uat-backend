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
                    'published_rent', 'published_today', 'unmapped_published',
                    'governorates_total', 'by_type', 'by_governorate', 'map_properties',
                    'approved_brokers', 'approved_offices', 'pending_professional_verifications',
                ],
                'journey',
                'team' => ['support_agents', 'support_managers'],
                'today',
                'periods' => ['day', '7d', '30d'],
            ]]);
    }

    public function test_super_admin_gets_fast_manager_team_summary(): void
    {
        [, $ownerHeaders] = $this->user('gm-team-owner@example.test', '+967733301011', ['super_admin']);
        [$manager] = $this->user('gm-team-manager@example.test', '+967733301012', ['support_manager']);
        [$agent] = $this->user('gm-team-agent@example.test', '+967733301013', ['support_agent']);

        $response = $this->withHeaders($ownerHeaders)
            ->getJson('/api/admin/workspace/general-manager/team')
            ->assertOk();

        $ids = collect($response->json('data'))->pluck('id')->map(fn ($id) => (int) $id);
        $this->assertTrue($ids->contains($manager->id));
        $this->assertTrue($ids->contains($agent->id));
    }

    public function test_place_search_requires_a_real_query(): void
    {
        [, $headers] = $this->user('gm-place-owner@example.test', '+967733301014', ['super_admin']);

        $this->withHeaders($headers)
            ->getJson('/api/admin/workspace/general-manager/place-search?q=x')
            ->assertUnprocessable();
    }

    public function test_support_manager_agent_and_regular_cannot_open_general_manager_apis(): void
    {
        [, $managerHeaders] = $this->user('gm-support-manager@example.test', '+967733301002', ['support_manager']);
        [, $agentHeaders] = $this->user('gm-support-agent@example.test', '+967733301003', ['support_agent']);
        [, $regularHeaders] = $this->user('gm-regular@example.test', '+967733301004');

        foreach ([$managerHeaders, $agentHeaders, $regularHeaders] as $headers) {
            $this->withHeaders($headers)->getJson('/api/admin/workspace/general-manager/insights')->assertForbidden();
            $this->withHeaders($headers)->getJson('/api/admin/workspace/general-manager/team')->assertForbidden();
            $this->withHeaders($headers)->getJson('/api/admin/workspace/general-manager/place-search?q=صنعاء')->assertForbidden();
        }
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
