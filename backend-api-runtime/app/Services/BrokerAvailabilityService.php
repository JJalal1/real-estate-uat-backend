<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyPublicationBlock;
use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class BrokerAvailabilityService
{
    public const REMINDER_TITLE = 'حدّث إعلاناتك';
    public const REMINDER_BODY = 'حان موعد تحديث إعلاناتك. افتح التحديثات من لوحة الدلال.';

    public function __construct(private readonly UserNotificationService $notifications, private readonly AuditLogService $audit) {}

    public function period(Property $property): int { return $property->purpose === 'rent' ? 7 : 14; }

    public function updateCandidates(User $actor, bool $onlyDue): Builder
    {
        return Property::query()
            ->where('user_id', $actor->id)
            ->publiclyVisible()
            ->when($onlyDue, fn (Builder $query) => $query->where('availability_due_at', '<=', now()));
    }

    public function change(User $actor, array $ids, string $state, Request $request, ?User $auditActor = null): array
    {
        abort_unless($actor->canManageExistingListings(), 403);
        return DB::transaction(function () use ($actor, $ids, $state, $request, $auditActor): array {
            $rows = Property::query()->withoutGlobalScopes()->whereIn('id', $ids)->orderBy('id')->lockForUpdate()->get();
            abort_unless($rows->count() === count(array_unique($ids)), 404);
            $visibilityChanged = false;
            foreach ($rows as $property) {
                abort_unless((int) $property->user_id === (int) $actor->id, 403);
                if ($property->status !== 'published' || in_array($property->review_status, ['rejected_blocked','returned_for_correction','submitted','under_review'], true)) {
                    throw new ConflictHttpException('تحديث التوفر متاح للإعلانات المعتمدة فقط، ولا يتجاوز قرار المراجعة.');
                }
                if (in_array($property->availability_status, ['sold','rented'], true)) {
                    throw new ConflictHttpException('لا يمكن إعادة فتح إعلان أُغلق بالبيع أو التأجير عبر التحديث.');
                }
                if (($state === 'sold' && $property->purpose !== 'sale') || ($state === 'rented' && $property->purpose !== 'rent')) {
                    throw new ConflictHttpException('اختر حالة الإغلاق الموافقة لنوع الإعلان.');
                }
                if ($state === 'available' && in_array($property->availability_status, ['paused', 'confirmation_paused'], true)) {
                    $this->assertMayResume($property);
                }
                $visibilityChanged = $visibilityChanged || $property->availability_status !== $state;
                $property->forceFill([
                    'availability_status'=>$state,
                    'availability_confirmed_at'=>$state === 'available' ? now() : $property->availability_confirmed_at,
                    'availability_due_at'=>$state === 'available' ? now()->addDays($this->period($property)) : null,
                    'availability_notified_at'=>null,
                ])->saveQuietly();
                $this->audit->record($auditActor ?? $actor, 'broker.availability_updated', $property, ['state'=>$state], $request, $actor->id);
            }
            if ($visibilityChanged) {
                PropertyDiscoveryFilterService::refreshNearbyVisibilityAfterCommit();
            }
            $notices=UserNotification::query()->where('user_id',$actor->id)->where('type','broker_availability_due')->whereNull('read_at')->lockForUpdate()->get();
            foreach ($notices as $notice) {
                $current = $notice->data['property_ids'] ?? [];
                $remaining = array_values(array_diff($current, $ids));
                if ($remaining !== $current) {
                    $notice->forceFill($remaining ? $this->reminderContent($remaining) : ['read_at' => now()])->save();
                }
            }
            return $rows->all();
        });
    }

    private function assertMayResume(Property $property): void
    {
        $publicationBlocked = $property->property_asset_id !== null
            && PropertyPublicationBlock::query()->where('property_asset_id', $property->property_asset_id)
                ->where('purpose', $property->purpose)->where('is_active', true)->exists();
        if ($publicationBlocked || ($property->financial_hold_at !== null && $property->financial_hold_reason !== 'platform_receivable_overdue')) {
            throw new ConflictHttpException('راجع سبب قيد النشر قبل إعادة عرض الإعلان.');
        }
    }

    public function sweep(int $limit = 100): void
    {
        $this->restorePreviousConfirmationPauses($limit);

        // A listing receives one reminder per confirmation period. Already
        // notified listings stay visible and do not consume subsequent batches.
        DB::transaction(function () use ($limit): void {
            $rows = Property::query()->withoutGlobalScopes()->publiclyVisible()
                ->whereNull('availability_notified_at')
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
                $property->availability_notified_at = now();
                $reminders[(int) $property->user_id][] = (int) $property->id;
                $property->saveQuietly();
            }
            foreach ($reminders as $userId=>$ids) {
                $notice=UserNotification::query()->where('user_id',$userId)->where('type','broker_availability_due')->whereNull('read_at')->latest('id')->lockForUpdate()->first();
                if ($notice) {
                    $ids=array_values(array_unique(array_merge($notice->data['property_ids'] ?? [],$ids)));
                    $notice->forceFill($this->reminderContent($ids))->save();
                    continue;
                }
                // Listing updates are essential reminders outside optional activity preferences.
                $content = $this->reminderContent($ids);
                $this->notifications->create($userId, 'broker_availability_due', $content['title'],
                    $content['body'], 'broker_availability', null, $content['data']);
            }
        });
    }

    private function restorePreviousConfirmationPauses(int $limit): void
    {
        // Only the retired timeout transition wrote confirmation_paused. The
        // old reminder timestamps establish provenance without a new migration.
        DB::transaction(function () use ($limit): void {
            $ids = DB::table('properties')
                ->where('status', 'published')
                ->where('review_status', 'approved')
                ->where('availability_status', 'confirmation_paused')
                ->whereNotNull('published_at')
                ->whereNull('financial_hold_at')
                ->whereColumn('availability_due_at', '<=', 'availability_notified_at')
                ->where('availability_notified_at', '<=', now()->subDays(2))
                ->whereNotExists(function ($block): void {
                    $block->selectRaw('1')->from('property_publication_blocks')
                        ->whereColumn('property_publication_blocks.property_asset_id', 'properties.property_asset_id')
                        ->whereColumn('property_publication_blocks.purpose', 'properties.purpose')
                        ->where('property_publication_blocks.is_active', true);
                })
                ->orderBy('id')->limit($limit)->lockForUpdate()->pluck('id');

            if ($ids->isNotEmpty()) {
                // Preserve the previous publication and confirmation dates,
                // including its due reminder and the owner's edit timestamp.
                DB::table('properties')->whereIn('id', $ids)->update(['availability_status' => 'available']);
                PropertyDiscoveryFilterService::refreshNearbyVisibilityAfterCommit();
            }
        });
    }

    private function reminderContent(array $ids): array
    {
        $count = count($ids);

        return [
            'title' => self::REMINDER_TITLE,
            'body' => self::REMINDER_BODY,
            'data' => ['property_ids' => $ids, 'count' => $count],
        ];
    }
}
