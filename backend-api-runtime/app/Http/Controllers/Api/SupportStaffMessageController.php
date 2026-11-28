<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTask;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\SupportTeamRoutingService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class SupportStaffMessageController extends Controller
{
    public function __construct(
        private readonly SupportTeamRoutingService $routing,
        private readonly UserNotificationService $notifications,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $actor = $request->user();
        $threads = DB::table('support_staff_threads')
            ->where(fn ($query) => $query->where('manager_user_id', $actor->id)->orWhere('recipient_user_id', $actor->id))
            ->latest('updated_at')->latest('id')->cursor();
        $result = [];
        foreach ($threads as $thread) {
            if (!$this->mayRead($actor, $thread)) continue;
            $result[] = $this->summary($actor, $thread);
            if (count($result) >= 60) break;
        }

        return response()->json(['data' => $result]);
    }

    public function open(Request $request): JsonResponse
    {
        $actor = $request->user();
        $executive = $actor->is_platform_owner || $actor->hasRole('super_admin');
        abort_unless($actor->isActive() && ($executive || $actor->hasRole('support_manager')), 403);
        $v = $request->validate([
            'channel' => ['required', Rule::in(['team', 'executive'])],
            'member_id' => ['required_if:channel,team', 'integer', 'min:1'],
            'team_id' => ['nullable', 'integer', 'min:1'],
        ]);
        if ($executive) {
            abort_unless($v['channel'] === 'executive' && isset($v['team_id']), 422);
            $teamId = (int) $v['team_id'];
            $managerId = DB::table('support_teams')->where('id', $teamId)
                ->where('is_active', true)->value('manager_user_id');
            $manager = User::query()->find($managerId);
            abort_unless($manager?->isActive() && $manager->hasRole('support_manager')
                && !$manager->is($actor) && in_array($teamId, $this->routing->managedTeamIds($manager), true), 404);

            return $this->openThread($actor, $teamId, (int) $manager->id, (int) $actor->id, 'executive');
        }

        $teamIds = $this->routing->managedTeamIds($actor);
        $teams = DB::table('support_teams')->whereIn('id', $teamIds)->where('is_active', true);
        if (isset($v['team_id'])) $teams->where('id', $v['team_id']);
        if ($v['channel'] === 'team') {
            $recipient = User::query()->findOrFail((int) $v['member_id']);
            $teams->whereIn('id', DB::table('support_team_members')->select('support_team_id')
                ->where('user_id', $recipient->id)->where('member_role', 'agent'));
        } else {
            $recipient = User::query()->where('account_status', User::STATUS_ACTIVE)
                ->where('id', '!=', $actor->id)
                ->where(fn ($query) => $query->where('is_platform_owner', true)
                    ->orWhereHas('roles', fn ($roles) => $roles->where('key', 'super_admin')))
                ->orderByDesc('is_platform_owner')->orderBy('id')->firstOrFail();
        }
        $teamId = $teams->orderBy('id')->value('id');
        abort_unless($teamId && $recipient->isActive() && !$recipient->is($actor), 404);
        return $this->openThread($actor, (int) $teamId, (int) $actor->id, (int) $recipient->id, $v['channel']);
    }

    private function openThread(User $actor, int $team, int $manager, int $recipient, string $channel): JsonResponse
    {
        $identity = [
            'support_team_id' => $team,
            'manager_user_id' => $manager,
            'recipient_user_id' => $recipient,
            'channel' => $channel,
        ];
        DB::table('support_staff_threads')->insertOrIgnore($identity + ['created_at' => now(), 'updated_at' => now()]);
        $thread = DB::table('support_staff_threads')->where($identity)->first();

        return response()->json(['data' => $this->summary($actor, $thread)]);
    }

    public function show(Request $request, int $threadId): JsonResponse
    {
        $actor = $request->user();
        $thread = $this->thread($actor, $threadId);
        $v = $request->validate(['before' => ['nullable', 'integer', 'min:1']]);
        $messages = DB::table('support_staff_messages')->where('support_staff_thread_id', $threadId)
            ->when(isset($v['before']), fn ($query) => $query->where('id', '<', $v['before']))
            ->latest('id')->limit(50)->get();
        if (!isset($v['before']) && $messages->isNotEmpty()) {
            $this->unread($actor, $threadId)->where('created_at', '<=', $messages->first()->created_at)
                ->update(['read_at' => now()]);
        }
        $rows = $messages->reverse()->values()->map(fn ($row) => [
                'id' => (int) $row->id, 'mine' => (int) $row->sender_user_id === (int) $actor->id,
                'body' => $row->body, 'task_id' => $row->support_task_id ? (int) $row->support_task_id : null,
                'created_at' => $row->created_at,
            ]);

        return response()->json(['data' => $this->summary($actor, $thread) + ['messages' => $rows]]);
    }

    public function send(Request $request, int $threadId): JsonResponse
    {
        $actor = $request->user();
        $v = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'client_key' => ['required', 'uuid'],
            'task_id' => ['nullable', 'integer', 'min:1'],
        ]);
        $body = trim($v['body']);
        abort_if($body === '', 422, 'اكتب رسالتك.');

        DB::transaction(function () use ($actor, $threadId, $v, $body): void {
            $thread = $this->thread($actor, $threadId, true);
            if (isset($v['task_id'])) {
                abort_unless($thread->channel === 'executive', 422);
                abort_unless(SupportTask::query()->whereKey($v['task_id'])->where('support_team_id', $thread->support_team_id)
                    ->where('source_type', '!=', 'contact_followup')->exists(), 404);
            }
            $inserted = DB::table('support_staff_messages')->insertOrIgnore([
                'support_staff_thread_id' => $thread->id,
                'sender_user_id' => $actor->id,
                'support_task_id' => $v['task_id'] ?? null,
                'client_key' => $v['client_key'],
                'body' => $body,
                'created_at' => now(),
            ]);
            if (!$inserted) return;
            DB::table('support_staff_threads')->where('id', $thread->id)->update(['updated_at' => now()]);
            $other = (int) $thread->manager_user_id === (int) $actor->id
                ? (int) $thread->recipient_user_id : (int) $thread->manager_user_id;
            $this->notifications->create($other, 'support_staff_message',
                'رسالة جديدة من فريق الدعم', 'افتح المحادثة لقراءة الرسالة.', 'support_staff_thread', (int) $thread->id);
        });

        return $this->show($request, $threadId);
    }

    private function thread(User $actor, int $id, bool $lock = false): object
    {
        $thread = DB::table('support_staff_threads')->where('id', $id)
            ->when($lock, fn ($query) => $query->lockForUpdate())->first();
        abort_unless($thread && $this->mayRead($actor, $thread), 404);

        return $thread;
    }

    private function mayRead(User $actor, object $thread): bool
    {
        if (!in_array((int) $actor->id, [(int) $thread->manager_user_id, (int) $thread->recipient_user_id], true)) return false;
        $manager = User::query()->find($thread->manager_user_id);
        $recipient = User::query()->find($thread->recipient_user_id);
        if (!$manager?->isActive() || !$manager->hasRole('support_manager') || !$recipient?->isActive()) return false;
        if (!in_array((int) $thread->support_team_id, $this->routing->managedTeamIds($manager), true)) return false;
        if ($thread->channel === 'executive') return $recipient->is_platform_owner || $recipient->hasRole('super_admin');

        return DB::table('support_team_members')->where('support_team_id', $thread->support_team_id)
            ->where('user_id', $recipient->id)->where('member_role', 'agent')->exists();
    }

    private function summary(User $actor, object $thread): array
    {
        $managerSide = (int) $thread->manager_user_id === (int) $actor->id;
        $other = $managerSide ? $thread->recipient_user_id : $thread->manager_user_id;
        $name = $managerSide && $thread->channel === 'executive'
            ? 'المدير العام' : User::query()->whereKey($other)->value('name');
        $last = DB::table('support_staff_messages')->where('support_staff_thread_id', $thread->id)->latest('id')->value('body');

        return [
            'id' => (int) $thread->id,
            'channel' => $thread->channel,
            'name' => $name,
            'team' => DB::table('support_teams')->where('id', $thread->support_team_id)->value('name_ar'),
            'preview' => $last === null ? null : mb_substr($last, 0, 120),
            'unread' => $this->unread($actor, (int) $thread->id)->count(),
        ];
    }

    private function unread(User $actor, int $thread): \Illuminate\Database\Eloquent\Builder
    {
        return UserNotification::query()->where('user_id', $actor->id)->where('entity_type', 'support_staff_thread')
            ->where('entity_id', $thread)->whereNull('read_at');
    }
}
