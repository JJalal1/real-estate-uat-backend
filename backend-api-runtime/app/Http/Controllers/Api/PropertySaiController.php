<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\PropertySaiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PropertySaiController extends Controller
{
    public function __construct(
        private readonly PropertySaiService $sai,
        private readonly ApiTokenService $tokens,
    ) {}

    public function show(Request $request, Property $property): JsonResponse
    {
        $viewer = $this->tokens->authenticate($request, false);
        $isOwner = $viewer !== null && (int) $viewer->id === (int) $property->user_id;
        abort_unless($property->status === 'published' || $isOwner, 404);

        $data = ['sai' => $this->sai->publicData($property)];
        // The default response is always public-safe, including for a logged-in
        // advertiser viewing their own published listing. Internal split and
        // consent state require an explicit owner-only management request.
        if ($request->boolean('management') && $isOwner) {
            $data['sai_management'] = $this->sai->managementData($property, $viewer);
        }

        return response()->json(['data' => $data]);
    }

    public function update(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'sai_payer' => ['required', 'string', Rule::in(['seller', 'buyer', 'landlord', 'tenant'])],
            'broker_sai_rate_percent' => ['nullable', 'numeric', 'min:0', 'max:100', 'decimal:0,2'],
            'platform_terms_decision' => ['nullable', 'string', Rule::in(['accept', 'reject'])],
        ]);

        $brokerRate = array_key_exists('broker_sai_rate_percent', $validated)
            && $validated['broker_sai_rate_percent'] !== null
            ? (float) $validated['broker_sai_rate_percent']
            : null;

        $term = $this->sai->configure(
            $user,
            $property,
            (string) $validated['sai_payer'],
            $brokerRate,
            isset($validated['platform_terms_decision']) ? (string) $validated['platform_terms_decision'] : null,
            $request,
        );

        $fresh = $property->fresh(['user.accountVerificationProfile']);

        return response()->json([
            'message' => $term->platform_terms_status === 'rejected'
                ? 'تم حفظ رفض الشرط. لا يمكن إرسال الإعلان للمراجعة حتى قبول الشروط أو اختيار سعي 0%.'
                : 'تم حفظ شروط السعي.',
            'data' => [
                'sai' => $this->sai->publicData($fresh),
                'sai_management' => $this->sai->managementData($fresh, $user),
            ],
        ]);
    }
}
