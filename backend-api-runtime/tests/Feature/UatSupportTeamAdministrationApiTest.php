<?php

namespace Tests\Feature;

use App\Models\Governorate;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\SupportTeam;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class UatSupportTeamAdministrationApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_assign_both_support_roles_and_bound_review_permissions(): void
    {
        [, $ownerHeaders] = $this->account('owner', '+967740520001', true);
        [$staff, $staffHeaders] = $this->account('support-worker', '+967740520002');
        $province = Governorate::query()->create(['code' => 'TEST_SUPPORT_ADMIN', 'name_ar' => 'محافظة الاختبار']);

        $this->withHeaders($staffHeaders)->getJson('/api/admin/workspace/teams/candidates?q=support')->assertForbidden();
        $this->withHeaders($ownerHeaders)->getJson('/api/admin/workspace/teams/candidates?q=520002')
            ->assertOk()->assertJsonPath('data.0.id', $staff->id);
        $url = '/api/admin/workspace/teams';
        $teamId = $this->withHeaders($ownerHeaders)->postJson($url, [
            'governorate_id' => $province->id, 'name' => 'فريق اختبار الدعم',
        ])->assertCreated()->json('data.id');
        $this->withHeaders($ownerHeaders)->putJson($url.'/'.$teamId.'/membership/'.$staff->id, [
            'agent' => true, 'manager' => true, 'review_payments' => false, 'review_listings' => true,
        ])->assertOk()->assertJsonPath('data.agent', true)->assertJsonPath('data.manager', true)
            ->assertJsonPath('data.review_payments', false)->assertJsonPath('data.review_listings', true);
        $this->assertDatabaseHas('support_teams', ['id' => $teamId, 'manager_user_id' => $staff->id]);
        $staff = $staff->fresh();
        $this->assertSame(['registered_user', 'support_agent', 'support_manager'], $staff->roleKeys());
        $this->assertFalse($staff->hasPermission('payments.review'));
        $this->withHeaders($ownerHeaders)->getJson($url.'/'.$teamId.'/members')
            ->assertOk()->assertJsonPath('data.0.user_id', $staff->id)->assertJsonPath('data.0.manager', true);
        $this->withHeaders($staffHeaders)->getJson('/api/admin/workspace/dashboard?acting_as_agent=1&workspace_v2=1')
            ->assertOk()->assertJsonPath('data.governorate_ids', [$province->id]);
    }

    public function test_unclaimed_provincial_work_reaches_the_designated_team_and_claims_keep_scope(): void
    {
        [, $ownerHeaders] = $this->account('owner', '+967740520011', true);
        [$staff, $staffHeaders] = $this->account('regional-worker', '+967740520012');
        [$fallbackStaff, $fallbackHeaders] = $this->account('fallback-worker', '+967740520013');
        $fallbackStaff->roles()->attach(Role::query()->where('key', 'support_agent')->value('id'));
        $province = Governorate::query()->create(['code' => 'TEST_SUPPORT_ROUTE', 'name_ar' => 'محافظة التوجيه']);
        $team = SupportTeam::query()->create([
            'code' => 'test-local-support', 'name_ar' => 'فريق المحافظة', 'governorate_id' => $province->id,
        ]);
        $fallback = SupportTeam::query()->where('is_fallback', true)->firstOrFail();
        $queued = SupportTask::query()->create([
            'source_type' => 'support_ticket', 'source_id' => 411, 'subject' => 'تذكرة محلية',
            'status' => 'new', 'priority' => 'normal', 'support_team_id' => $fallback->id,
            'governorate_id' => $province->id, 'last_activity_at' => now(),
        ]);
        $claimed = SupportTask::query()->create([
            'source_type' => 'support_ticket', 'source_id' => 412, 'subject' => 'تذكرة مستلمة',
            'status' => 'in_progress', 'priority' => 'normal', 'support_team_id' => $fallback->id,
            'governorate_id' => $province->id, 'assigned_to_user_id' => $fallbackStaff->id, 'claimed_at' => now(),
            'last_activity_at' => now(),
        ]);
        $inbox = '/api/admin/workspace/tasks?scope=inbox&type=support_ticket';
        $this->withHeaders($fallbackHeaders)->getJson($inbox)->assertOk()
            ->assertJsonPath('data.0.id', $queued->id)->assertJsonPath('data.0.governorate_id', $province->id);
        $this->withHeaders($ownerHeaders)->putJson('/api/admin/workspace/teams/'.$team->id.'/membership/'.$staff->id, [
            'agent' => true, 'manager' => false, 'is_available' => false,
        ])->assertOk();

        $this->withHeaders($staffHeaders)->getJson($inbox)
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.id', $queued->id);
        $this->withHeaders($fallbackHeaders)->getJson($inbox)->assertOk()->assertJsonPath('meta.total', 0);
        $this->assertEquals($team->id, $queued->fresh()->support_team_id);
        $this->assertEquals($fallback->id, $claimed->fresh()->support_team_id);
    }

    private function account(string $name, string $phone, bool $platformOwner = false): array
    {
        $user = User::factory()->create([
            'name' => $name, 'phone' => $phone, 'phone_verified_at' => now(), 'account_status' => User::STATUS_ACTIVE,
            'is_platform_owner' => $platformOwner,
        ]);
        $user->roles()->attach(Role::query()->where('key', 'registered_user')->value('id'));
        $token = hash('sha512', $phone);
        $user->apiTokens()->create([
            'name' => 'support-team-test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour(),
        ]);

        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }
}
