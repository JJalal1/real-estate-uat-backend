<?php

namespace Tests\Feature;

use App\Models\Governorate;
use App\Models\Permission;
use App\Models\Property;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\SupportTeam;
use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class UatSupportTeamAdministrationApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_manager_period_and_internal_chats_stay_inside_the_team(): void
    {
        [, $executive] = $this->account('director', '+967740520021', true);
        [$manager, $managerHeaders] = $this->account('local-manager', '+967740520022');
        [$agent, $agentHeaders] = $this->account('local-worker', '+967740520023');
        [$other, $otherHeaders] = $this->account('other-worker', '+967740520024');
        $reportTasks = [];
        foreach ([$manager, $agent, $other] as $staff) {
            $province = Governorate::query()->firstOrCreate(['code' => $staff->is($other) ? 'SCOPE_B' : 'SCOPE_A'],
                ['name_ar' => $staff->is($other) ? 'المحافظة الثانية' : 'المحافظة الأولى']);
            $teamId = SupportTeam::query()->where('governorate_id', $province->id)->value('id')
                ?? $this->withHeaders($executive)->postJson('/api/admin/workspace/teams', [
                    'governorate_id' => $province->id, 'name' => $province->name_ar,
                ])->assertCreated()->json('data.id');
            $this->withHeaders($executive)->putJson("/api/admin/workspace/teams/$teamId/membership/{$staff->id}", [
                'manager' => $staff->is($manager), 'agent' => !$staff->is($manager),
            ])->assertOk();
            if (!$staff->is($agent)) {
                $reportTask = SupportTask::query()->create([
                    'source_type' => 'report', 'source_id' => $staff->id, 'subject' => 'تقرير للمحافظة',
                    'status' => 'completed', 'priority' => 'normal', 'support_team_id' => $teamId,
                    'governorate_id' => $province->id, 'last_activity_at' => now(), 'completed_at' => now(),
                ]);
                $reportTask->forceFill(['created_at' => '2026-11-27 21:15:00', 'completed_at' => '2026-11-27 22:00:00'])->save();
                $reportTasks[$staff->id] = $reportTask->id;
                $listing = Property::query()->create([
                    'user_id' => $staff->id, 'title' => 'إعلان منشور للمحافظة', 'type' => 'house',
                    'description' => 'إعلان للاختبار', 'address' => 'عنوان الاختبار', 'purpose' => 'sale',
                    'price' => 900000, 'currency' => 'YER', 'latitude' => 15.37, 'longitude' => 44.19,
                    'status' => 'published', 'review_status' => 'approved', 'published_at' => '2026-11-27 22:15:00',
                ]);
                SupportTask::query()->create([
                    'source_type' => 'listing_review', 'source_id' => $listing->id, 'subject' => $listing->title,
                    'status' => 'completed', 'priority' => 'normal', 'support_team_id' => $teamId,
                    'governorate_id' => $province->id, 'last_activity_at' => now(),
                ])->forceFill(['created_at' => '2026-11-27 20:00:00', 'completed_at' => '2026-11-27 22:15:00'])->save();
            }
        }
        $stats = '/api/admin/workspace/team-statistics?from=2026-11-28&to=2026-11-28';
        $this->withHeaders($managerHeaders)->getJson($stats)->assertOk()
            ->assertJsonPath('data.received', 1)->assertJsonPath('data.completed', 2)
            ->assertJsonPath('data.reports', 1)->assertJsonPath('data.published', 1);
        $this->withHeaders($managerHeaders)->getJson(str_replace('11-28', '11-27', $stats))->assertOk()
            ->assertJsonPath('data.received', 1)->assertJsonPath('data.completed', 0)
            ->assertJsonPath('data.published', 0);
        $this->withHeaders($otherHeaders)->getJson($stats)->assertForbidden();

        $messages = '/api/admin/workspace/staff-messages';
        $this->withHeaders($managerHeaders)->postJson($messages, ['channel' => 'team', 'member_id' => $other->id])
            ->assertNotFound();
        $chat = $this->withHeaders($managerHeaders)->postJson($messages, ['channel' => 'team', 'member_id' => $agent->id])
            ->assertOk()->json('data.id');
        $data = ['body' => 'تابع طلبات الفريق من القائمة.', 'client_key' => (string) Str::uuid()];
        $this->withHeaders($managerHeaders)->postJson("$messages/$chat", $data)->assertOk();
        $this->withHeaders($managerHeaders)->postJson("$messages/$chat", $data)->assertOk();
        $this->withHeaders($agentHeaders)->getJson("$messages/$chat")->assertOk()
            ->assertJsonCount(1, 'data.messages')->assertJsonPath('data.messages.0.body', $data['body']);
        $this->withHeaders($otherHeaders)->getJson("$messages/$chat")->assertNotFound();
        $this->withHeaders($executive)->getJson("$messages/$chat")->assertNotFound();
        $director = $this->withHeaders($managerHeaders)->postJson($messages, ['channel' => 'executive'])
            ->assertOk()->json('data.id');
        $this->withHeaders($managerHeaders)->postJson("$messages/$director", $data + [
            'task_id' => $reportTasks[$other->id],
        ])->assertNotFound();
        $this->withHeaders($managerHeaders)->postJson("$messages/$director", $data + [
            'task_id' => $reportTasks[$manager->id],
        ])->assertOk();
        $this->withHeaders($executive)->getJson("$messages/$director")->assertOk()
            ->assertJsonPath('data.messages.0.body', $data['body'])
            ->assertJsonPath('data.messages.0.task_id', $reportTasks[$manager->id]);
    }

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

    public function test_executive_decisions_stats_and_messages_use_the_same_regional_task(): void
    {
        [$director, $executive] = $this->account('general-manager', '+967740520050', true);
        [$manager, $local] = $this->account('local-manager', '+967740520051');
        [$worker, $support] = $this->account('local-worker', '+967740520052');
        [$otherManager, $foreign] = $this->account('other-manager', '+967740520053');
        $base = '/api/admin/workspace';
        $province = Governorate::query()->create(['code' => 'EXEC_A', 'name_ar' => 'محافظة ألف']);
        $otherProvince = Governorate::query()->create(['code' => 'EXEC_B', 'name_ar' => 'محافظة باء']);
        foreach ([[$province, $manager], [$otherProvince, $otherManager]] as [$region, $lead]) {
            $team = $this->withHeaders($executive)->postJson("$base/teams", [
                'governorate_id'=>$region->id, 'name'=>$region->name_ar,
            ])->assertCreated()->json('data.id');
            $this->withHeaders($executive)->putJson("$base/teams/$team/membership/{$lead->id}", [
                'manager'=>true, 'agent'=>false,
            ])->assertOk();
        }
        $team = SupportTeam::query()->where('governorate_id', $province->id)->firstOrFail();
        $foreignTeam = SupportTeam::query()->where('governorate_id', $otherProvince->id)->firstOrFail();
        $this->withHeaders($executive)->putJson("$base/teams/{$team->id}/membership/{$worker->id}", [
            'manager'=>false, 'agent'=>true,
        ])->assertOk();
        $task = SupportTask::query()->create([
            'source_type'=>'report', 'source_id'=>801, 'subject'=>'بلاغ يحتاج توجيهًا',
            'status'=>'escalated', 'priority'=>'urgent', 'support_team_id'=>$team->id,
            'governorate_id'=>$province->id, 'assigned_to_user_id'=>$worker->id,
            'escalation_reason'=>'راجع مدير المحافظة', 'last_activity_at'=>now(),
        ]);
        SupportTask::query()->create([
            'source_type'=>'report', 'source_id'=>802, 'subject'=>'بلاغ تم إنجازه',
            'status'=>'completed', 'priority'=>'normal', 'support_team_id'=>$team->id,
            'governorate_id'=>$province->id, 'assigned_to_user_id'=>$worker->id,
            'last_activity_at'=>now(), 'completed_at'=>now(),
        ]);

        $decisions = "$base/general-manager/decisions";
        $operations = "$base/general-manager/operations?period=day&governorate_id={$province->id}";
        $forward = "$base/tasks/{$task->id}/forward-to-executive";
        $regionalRole = Role::query()->where('key', 'support_manager')->firstOrFail();
        $regionalRole->permissions()->syncWithoutDetaching(Permission::query()->where('key', 'users.manage_roles')->value('id'));
        $this->withHeaders($local)->getJson("$base/teams")->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $team->id);
        $this->withHeaders($local)->getJson("$base/teams/{$foreignTeam->id}/members")->assertForbidden();
        $this->withHeaders($executive)->getJson($decisions)->assertOk()->assertJsonPath('meta.total', 0);
        $this->withHeaders($local)->getJson($operations)->assertForbidden();
        $this->withHeaders($local)->getJson("$base/team?period=day")->assertOk()
            ->assertJsonFragment(['name'=>$worker->name, 'completed_in_period'=>1]);
        $this->withHeaders($foreign)->getJson("$base/team?period=day")->assertOk()->assertJsonMissing(['name'=>$worker->name]);
        $this->withHeaders($support)->postJson($forward, ['reason'=>'طلب تدخل'])->assertForbidden();
        $this->withHeaders($foreign)->postJson($forward, ['reason'=>'طلب تدخل'])->assertForbidden();
        $this->withHeaders($local)->postJson($forward, ['reason'=>'تحديد المسؤول عن البلاغ'])->assertOk();
        $this->withHeaders($local)->postJson($forward, ['reason'=>'تكرار التصعيد'])->assertConflict();
        $this->withHeaders($executive)->getJson($operations)->assertOk()
            ->assertJsonPath('data.decisions', 1)->assertJsonPath('data.totals.received', 2)
            ->assertJsonPath('data.totals.completed', 1)->assertJsonPath('data.teams.0.id', $team->id);
        $this->withHeaders($executive)->getJson("$decisions?governorate_id={$otherProvince->id}")
            ->assertOk()->assertJsonPath('meta.total', 0);
        $this->withHeaders($executive)->getJson($decisions)->assertOk()->assertJsonPath('data.0.id', $task->id);
        $this->withHeaders($local)->getJson("$decisions/{$task->id}")->assertForbidden();
        $this->withHeaders($local)->postJson("$base/tasks/{$task->id}/resolve-escalation", ['note'=>'قرار غير مصرح'])->assertForbidden();

        $messages = "$base/staff-messages";
        $thread = $this->withHeaders($executive)->postJson($messages, ['channel'=>'executive', 'team_id'=>$team->id])
            ->assertOk()->assertJsonPath('data.name', $manager->name)->json('data.id');
        $this->withHeaders($local)->postJson($messages, ['channel'=>'executive', 'team_id'=>$team->id])
            ->assertOk()->assertJsonPath('data.id', $thread);
        $this->withHeaders($local)->postJson("$messages/$thread", [
            'body'=>'هذا البلاغ للمراجعة', 'client_key'=>(string) Str::uuid(), 'task_id'=>$task->id,
        ])->assertOk();
        $this->withHeaders($executive)->getJson($messages)->assertOk()->assertJsonPath('data.0.unread', 1);
        $this->withHeaders($executive)->getJson("$messages/$thread")->assertOk()
            ->assertJsonPath('data.messages.0.task_id', $task->id)->assertJsonPath('data.unread', 0);

        $resolved = ['note'=>'يتابع فريق المحافظة البلاغ'];
        $this->withHeaders($executive)->postJson("$decisions/{$task->id}/resolve", $resolved)
            ->assertOk()->assertJsonPath('data.status', 'in_progress');
        $this->withHeaders($executive)->postJson("$decisions/{$task->id}/resolve", $resolved)->assertConflict();
        $this->withHeaders($executive)->getJson($decisions)->assertOk()->assertJsonPath('meta.total', 0);
        $this->assertDatabaseHas('user_notifications', ['user_id'=>$director->id, 'entity_type'=>'executive_support_task',
            'entity_id'=>$task->id]);
        $this->assertDatabaseHas('user_notifications', ['user_id'=>$manager->id, 'entity_type'=>'support_task',
            'entity_id'=>$task->id, 'type'=>'support_escalation_resolved']);

        $personal = UserNotification::query()->create([
            'user_id'=>$manager->id, 'type'=>'property_alert', 'title'=>'إشعار عقاري',
            'body'=>'إشعار شخصي', 'entity_type'=>'property', 'entity_id'=>1, 'created_at'=>now(),
        ]);
        $this->withHeaders($local)->getJson('/api/notifications?platform_history=1&work_only=1')
            ->assertOk()->assertJsonMissing(['id'=>$personal->id]);
        $this->withHeaders($local)->postJson('/api/notifications/history/read-all?work_only=1')->assertOk();
        $this->assertNull($personal->fresh()->read_at);
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
