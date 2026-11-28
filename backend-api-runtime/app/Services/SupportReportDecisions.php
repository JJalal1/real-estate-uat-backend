<?php

namespace App\Services;

use App\Models\AdvertiserRating;
use App\Models\ConversationReport;
use App\Models\ListingComment;
use App\Models\MessageThreadParticipant;
use App\Models\Property;
use App\Models\SupportCase;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class SupportReportDecisions
{
    public function __construct(
        private readonly SupportTaskService $tasks,
        private readonly SupportCaseService $cases,
        private readonly UserNotificationService $notifications,
        private readonly AuditLogService $audit,
    ) {}

    public function reportedUserId(SupportCase $case): ?int
    {
        if ($case->kind !== 'report' || !$case->target_id) return null;
        $id = match ($case->target_type) {
            'advertiser' => $case->target_id,
            'listing' => Property::query()->whereKey($case->target_id)->value('user_id'),
            'comment' => ListingComment::query()->whereKey($case->target_id)->value('author_user_id'),
            'rating' => AdvertiserRating::query()->whereKey($case->target_id)->value('rater_user_id'),
            'conversation_thread' => MessageThreadParticipant::query()->where('thread_id', $case->target_id)
                ->where('user_id', '!=', $case->requester_user_id)->value('user_id'),
            default => null,
        };

        return $id === null ? null : (int) $id;
    }

    public function canManagePublication(User $actor): bool
    {
        return $actor->is_platform_owner || $actor->hasRole('super_admin') || $actor->hasPermission('users.manage_status');
    }

    public function decide(User $actor, SupportCase $case, string $decision, string $note, Request $request): SupportCase
    {
        abort_unless($case->kind === 'report', 404);
        $changesPublication = in_array($decision, ['pause_publication', 'restore_publication'], true);
        if ($changesPublication) abort_unless($this->canManagePublication($actor), 403);

        return DB::transaction(function () use ($actor, $case, $decision, $note, $request, $changesPublication): SupportCase {
            $locked = SupportCase::query()->lockForUpdate()->findOrFail($case->id);
            if ($decision === 'restore_publication') {
                $task = SupportTask::query()->where('source_type', 'report')->where('source_id', $locked->id)->firstOrFail();
                $this->tasks->assertTaskOwnership($actor, $task);
            } else {
                $this->tasks->assertCaseAccess($actor, $locked);
                if (in_array($locked->status, SupportCaseService::CLOSED_STATUSES, true)) {
                    throw new ConflictHttpException('تم إغلاق البلاغ مسبقًا.');
                }
            }

            if ($changesPublication) {
                $target = User::query()->lockForUpdate()->findOrFail($this->reportedUserId($locked));
                abort_if($target->is_platform_owner || $target->hasRole('super_admin') || $target->is($actor), 403);
                $restore = $decision === 'restore_publication';
                $existing = $target->support_publication_hold_case_id;
                if ($restore && (int) $existing !== (int) $locked->id) {
                    throw new ConflictHttpException('لا يوجد إيقاف نشر مرتبط بهذا البلاغ.');
                }
                if (!$restore && $existing !== null && (int) $existing !== (int) $locked->id) {
                    throw new ConflictHttpException('النشر موقوف بالفعل بقرار آخر.');
                }
                $target->forceFill(['support_publication_hold_case_id' => $restore ? null : $locked->id])->save();
                PropertyDiscoveryFilterService::refreshNearbyVisibilityAfterCommit();
                $type = $restore ? 'support_publication_restored' : 'support_publication_hold';
                $title = $restore ? 'أُعيد تفعيل النشر' : 'أُوقف النشر مؤقتًا';
                $this->notifications->create((int) $target->id, $type, $title, $note, 'support_report_decision', (int) $locked->id);
                $this->audit->record($actor, 'support.'.$type, $locked, ['reason' => $note], $request, $target->id);
                if ($restore) return $locked;
            }

            $status = match ($decision) {
                'request_information' => 'waiting_requester',
                'dismiss' => 'dismissed',
                default => 'resolved',
            };
            if (in_array($status, SupportCaseService::CLOSED_STATUSES, true)) {
                ConversationReport::query()->where('support_case_id', $locked->id)
                    ->whereIn('status', ['open', 'under_review'])->update([
                        'status' => $status,
                        'resolved_by_user_id' => $actor->id,
                        'resolved_by_name_snapshot' => $actor->name,
                        'resolution_note' => $note,
                        'resolved_at' => now(),
                    ]);
            }

            return $this->cases->setStatus($actor, $locked, $status, $request, $note);
        });
    }
}
