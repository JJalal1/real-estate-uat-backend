<?php

namespace App\Services;

use App\Models\Property;
use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class BrokerAvailabilityService
{
    public function __construct(private readonly UserNotificationService $notifications, private readonly AuditLogService $audit) {}

    public function period(Property $property): int { return $property->purpose === 'rent' ? 7 : 14; }

    public function change(User $actor, array $ids, string $state, Request $request): array
    {
        abort_unless($actor->hasApprovedVerificationProfile(), 403);
        return DB::transaction(function () use ($actor, $ids, $state, $request): array {
            $rows = Property::query()->withoutGlobalScopes()->whereIn('id', $ids)->orderBy('id')->lockForUpdate()->get();
            abort_unless($rows->count() === count(array_unique($ids)), 404);
            foreach ($rows as $property) {
                abort_unless((int) $property->user_id === (int) $actor->id, 403);
                if ($property->status !== 'published' || in_array($property->review_status, ['rejected_blocked','returned_for_correction','submitted','under_review'], true)) {
                    throw new ConflictHttpException('تحديث التوفر متاح للإعلانات المعتمدة فقط، ولا يتجاوز قرار المراجعة.');
                }
                if (in_array($property->availability_status, ['sold','rented'], true)) {
                    throw new ConflictHttpException('الإعلان المغلق ببيع أو إيجار لا يعاد فتحه بتأكيد التوفر.');
                }
                if (($state === 'sold' && $property->purpose !== 'sale') || ($state === 'rented' && $property->purpose !== 'rent')) {
                    throw new ConflictHttpException('اختر حالة الإغلاق الموافقة لنوع الإعلان.');
                }
                $property->forceFill([
                    'availability_status'=>$state,
                    'availability_confirmed_at'=>$state === 'available' ? now() : $property->availability_confirmed_at,
                    'availability_due_at'=>$state === 'available' ? now()->addDays($this->period($property)) : null,
                    'availability_notified_at'=>null,
                ])->saveQuietly();
                $this->audit->record($actor, 'broker.availability_updated', $property, ['state'=>$state], $request, $actor->id);
            }
            $notices=UserNotification::query()->where('user_id',$actor->id)->where('type','broker_availability_due')->whereNull('read_at')->lockForUpdate()->get();
            foreach ($notices as $notice) {
                $remaining=array_values(array_diff($notice->data['property_ids'] ?? [],$ids));
                $notice->forceFill(['read_at'=>$remaining ? null : now(),
                    'body'=>'لديك '.count($remaining).' إعلانات تحتاج تحديث التوفر. يمكنك تأكيدها معًا خلال يومين.',
                    'data'=>['property_ids'=>$remaining,'count'=>count($remaining),'grace_days'=>2]])->save();
            }
            return $rows->all();
        });
    }

    public function sweep(int $limit = 100): void
    {
        // Limit each request/command batch; reminder creation and grace timestamps share one lock.
        DB::transaction(function () use ($limit): void {
            $rows = Property::query()->withoutGlobalScopes()->where('status','published')
                ->where('availability_status','available')
                ->where(function ($query): void { $query->whereNull('availability_notified_at')->orWhere('availability_notified_at','<=',now()->subDays(2)); })
                ->where(function ($query): void { $query->whereNull('availability_due_at')->orWhere('availability_due_at','<=',now()); })
                ->orderBy('id')->limit($limit)->lockForUpdate()->get();
            $reminders = [];
            foreach ($rows as $property) {
                if ($property->availability_due_at === null) {
                    $confirmed = $property->availability_confirmed_at ?? $property->published_at ?? $property->created_at ?? now();
                    $property->availability_confirmed_at = $confirmed;
                    $property->availability_due_at = $confirmed->copy()->addDays($this->period($property));
                }
                if ($property->availability_due_at->isFuture()) { $property->saveQuietly(); continue; }
                if ($property->availability_notified_at !== null && $property->availability_notified_at->lte(now()->subDays(2))) {
                    $property->availability_status = 'confirmation_paused';
                } elseif ($property->availability_notified_at === null) {
                    $property->availability_notified_at = now();
                    $reminders[(int) $property->user_id][] = (int) $property->id;
                }
                $property->saveQuietly();
            }
            foreach ($reminders as $userId=>$ids) {
                $notice=UserNotification::query()->where('user_id',$userId)->where('type','broker_availability_due')->whereNull('read_at')->latest('id')->lockForUpdate()->first();
                if ($notice) {
                    $ids=array_values(array_unique(array_merge($notice->data['property_ids'] ?? [],$ids)));
                    $notice->forceFill(['body'=>'لديك '.count($ids).' إعلانات تحتاج تحديث التوفر. يمكنك تأكيدها معًا خلال يومين.',
                        'data'=>['property_ids'=>$ids,'count'=>count($ids),'grace_days'=>2]])->save();
                    continue;
                }
                // Availability confirmation is an essential notice and cannot be suppressed by optional activity preferences.
                $this->notifications->create($userId, 'broker_availability_due', 'أكد توفر إعلاناتك',
                    'لديك '.count($ids).' إعلانات تحتاج تحديث التوفر. يمكنك تأكيدها معًا خلال يومين.',
                    'broker_availability', null, ['property_ids'=>$ids,'count'=>count($ids),'grace_days'=>2]);
            }
        });
    }
}
