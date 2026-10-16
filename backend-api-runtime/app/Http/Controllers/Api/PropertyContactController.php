<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PropertyContactController extends Controller
{
    public function __invoke(Request $request, int $property): JsonResponse
    {
        // Only the number explicitly entered for this listing may be revealed.
        // Account, verification and office documents never supply a fallback.
        $listing = app(\App\Services\PropertyDiscoveryFilterService::class)->publicQuery()->whereKey($property)->firstOrFail();
        abort_unless($listing->user?->account_status === 'active', 404);
        $phone = preg_replace('/[\s()\-]/u', '', (string) $listing->contact_phone);
        abort_unless(preg_match('/^\+?[0-9]{7,15}$/D', $phone), 422, 'لم يضف المعلن رقم اتصال صالحًا لهذا الإعلان. يمكنك مراسلته داخل التطبيق.');
        return response()->json(['data' => ['property_id' => (int) $listing->id, 'phone' => $phone]])
            ->header('Cache-Control', 'no-store, private');
    }
}
