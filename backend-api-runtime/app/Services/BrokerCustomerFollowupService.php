<?php

namespace App\Services;

use App\Models\BrokerCustomerFollowup;
use Illuminate\Support\Facades\DB;

class BrokerCustomerFollowupService
{
    public function __construct(private readonly UserNotificationService $notifications) {}

    public function sweep(int $limit = 100): int
    {
        return DB::transaction(function () use ($limit): int {
            $rows = BrokerCustomerFollowup::query()->whereNull('reminded_at')->whereNotNull('remind_at')
                ->where('remind_at', '<=', now())->orderBy('remind_at')->orderBy('id')
                ->limit(max(1, min(500, $limit)))->lockForUpdate()->get();
            $sent = 0;
            foreach ($rows as $row) {
                $row->load(['user', 'thread.property'=>fn ($query) => $query->withoutGlobalScopes(), 'thread.participants']);
                $actor = $row->user;
                $thread = $row->thread;
                if ($actor?->isActive() && $actor->hasApprovedVerificationProfile() && $thread &&
                    (int) $thread->property?->user_id === (int) $actor->id &&
                    $thread->participants->contains(fn ($p) => (int) $p->user_id === (int) $actor->id)) {
                    // A private reminder never sends a customer message or includes the private note.
                    $this->notifications->create((int) $actor->id, 'broker_customer_followup_due',
                        'حان موعد متابعة عميلك', 'افتح المحادثة لمتابعة العميل في الموعد الذي حددته.',
                        'message_thread', (int) $thread->id, ['message_thread_id'=>(int) $thread->id, 'property_id'=>(int) $thread->property_id]);
                    $sent++;
                }
                // Invalidated ownership/accounts cannot starve the bounded due queue.
                $row->forceFill(['reminded_at'=>now()])->save();
            }
            return $sent;
        });
    }

    public function clearNotice(int $userId, int $threadId): void
    {
        DB::table('user_notifications')->where('user_id', $userId)->where('type', 'broker_customer_followup_due')
            ->where('entity_type', 'message_thread')->where('entity_id', $threadId)->whereNull('read_at')->update(['read_at'=>now()]);
    }
}
