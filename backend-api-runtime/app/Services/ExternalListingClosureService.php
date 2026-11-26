<?php

namespace App\Services;

use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\User;
use Illuminate\Http\Request;

final class ExternalListingClosureService
{
    public function __construct(private readonly SupportCaseService $support) {}

    public function record(User $advertiser, Property $property, Request $request): void
    {
        abort_if(BrokerDealOutcome::query()->where('property_id', $property->id)
            ->whereIn('status', ['pending_customer', 'disputed'])->exists(),
            409, 'راجع طلب تأكيد هذه الصفقة قبل تسجيل صفقة خارج التطبيق.');

        $thread = MessageThread::query()
            ->where('property_id', $property->id)
            ->where('started_by_user_id', '<>', $advertiser->id)
            ->whereIn('started_by_user_id', User::query()->select('id')
                ->where('account_status', User::STATUS_ACTIVE)->whereNotNull('phone_verified_at'))
            ->whereHas('participants', fn ($participants) => $participants->where('user_id', $advertiser->id))
            ->whereHas('participants', fn ($participants) => $participants->whereColumn('user_id', 'message_threads.started_by_user_id'))
            ->orderByRaw('case when last_message_at is null then 1 else 0 end')
            ->latest('last_message_at')
            ->latest('id')
            ->first();

        $customer = $thread ? User::query()->find($thread->started_by_user_id) : null;
        if (! $customer?->isActive()) {
            return;
        }

        $status = $property->availability_status === 'rented' ? 'تم تأجيره' : 'تم بيعه';
        $this->support->create(
            $customer,
            'support_ticket',
            'تغيير حالة إعلان خارج التطبيق',
            'حدّث المعلن حالة الإعلان «'.$property->title.'» إلى «'.$status.'» خارج التطبيق.',
            'property',
            (int) $property->id,
            'external_listing_closure',
            'normal',
            $request,
            initiator: $advertiser,
        );
    }
}
