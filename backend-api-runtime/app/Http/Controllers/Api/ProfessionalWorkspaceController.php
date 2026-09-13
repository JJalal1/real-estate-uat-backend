<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ProfessionalWorkspaceController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $profile = $user->verificationProfile();
        abort_unless($profile && $profile->isApproved(), 403, 'يلزم حساب نشر موثق لفتح لوحة العمل.');

        $listingIds = Property::query()->where('user_id', $user->id)->pluck('id');
        $publishedIds = Property::query()
            ->where('user_id', $user->id)
            ->where('status', 'published')
            ->pluck('id');

        $listingCounts = Property::query()
            ->where('user_id', $user->id)
            ->selectRaw('status, COUNT(*) AS aggregate')
            ->groupBy('status')
            ->pluck('aggregate', 'status');
        $reviewCounts = Property::query()
            ->where('user_id', $user->id)
            ->selectRaw('review_status, COUNT(*) AS aggregate')
            ->groupBy('review_status')
            ->pluck('aggregate', 'review_status');

        $favoriteCount = $publishedIds->isEmpty()
            ? 0
            : (int) DB::table('property_favorites')->whereIn('property_id', $publishedIds)->count();
        $conversationCount = $listingIds->isEmpty()
            ? 0
            : (int) DB::table('message_threads')->whereIn('property_id', $listingIds)->count();
        $unreadConversationCount = (int) DB::table('message_thread_participants as participant')
            ->join('message_threads as thread', 'thread.id', '=', 'participant.thread_id')
            ->where('participant.user_id', $user->id)
            ->whereIn('thread.property_id', $listingIds)
            ->whereExists(function ($query): void {
                $query->selectRaw('1')
                    ->from('private_messages as pm')
                    ->whereColumn('pm.thread_id', 'thread.id')
                    ->whereColumn('pm.sender_user_id', '<>', 'participant.user_id')
                    ->where(function ($nested): void {
                        $nested->whereNull('participant.last_read_message_id')
                            ->orWhereColumn('pm.id', '>', 'participant.last_read_message_id');
                    });
            })
            ->count();

        $activeViewingCount = (int) DB::table('viewing_bookings')
            ->where(function ($query) use ($user, $listingIds): void {
                $query->where('host_user_id', $user->id)
                    ->orWhere(function ($nested) use ($listingIds): void {
                        $nested->where('target_type', 'property')->whereIn('target_id', $listingIds);
                    });
            })
            ->whereIn('status', ['requested', 'confirmed'])
            ->count();

        $agreementCount = (int) DB::table('property_agreements')
            ->where('advertiser_user_id', $user->id)
            ->whereIn('status', ['draft', 'accepted'])
            ->count();

        $needsCorrection = Property::query()
            ->where('user_id', $user->id)
            ->where('review_status', 'returned_for_correction')
            ->latest('id')
            ->limit(10)
            ->get(['id', 'title', 'last_review_reason'])
            ->map(fn (Property $property) => [
                'id' => (int) $property->id,
                'title' => $property->title,
                'reason' => $property->last_review_reason,
            ])->values();

        $stalePublished = Property::query()
            ->where('user_id', $user->id)
            ->where('status', 'published')
            ->where('updated_at', '<', now()->subDays(30))
            ->latest('updated_at')
            ->limit(10)
            ->get(['id', 'title', 'updated_at'])
            ->map(fn (Property $property) => [
                'id' => (int) $property->id,
                'title' => $property->title,
                'updated_at' => $property->updated_at?->toIso8601String(),
            ])->values();

        return response()->json(['data' => [
            'publisher_type' => $profile->type,
            'publisher_label' => match ($profile->type) {
                'owner' => 'مالك موثق',
                'broker' => 'دلال موثق',
                'office' => 'مكتب عقاري موثق',
                default => 'معلن موثق',
            },
            'listings' => [
                'total' => (int) array_sum($listingCounts->all()),
                'published' => (int) ($listingCounts['published'] ?? 0),
                'draft' => (int) ($listingCounts['draft'] ?? 0),
                'pending' => (int) ($listingCounts['pending'] ?? 0),
                'returned_for_correction' => (int) ($reviewCounts['returned_for_correction'] ?? 0),
            ],
            'customer_activity' => [
                'favorites' => $favoriteCount,
                'conversations' => $conversationCount,
                'unread_conversations' => $unreadConversationCount,
                'active_viewings' => $activeViewingCount,
                'active_agreements' => $agreementCount,
            ],
            'needs_attention' => [
                'correction_listings' => $needsCorrection,
                'stale_published_listings' => $stalePublished,
            ],
        ]]);
    }
}
