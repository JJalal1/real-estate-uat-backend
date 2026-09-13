<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\PropertyIdentityService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PropertyIdentityController extends Controller
{
    public function __construct(
        private readonly PropertyIdentityService $identity,
        private readonly AuditLogService $audit,
    ) {}

    public function check(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertOwner($property, $user);
        $result = $this->identity->evaluate($property, $user, true);

        return response()->json(['data' => $result]);
    }

    public function selfVerify(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertOwner($property, $user);
        $validated = $request->validate([
            'assert_different' => ['required', 'accepted'],
            'difference_type' => ['required', 'string', Rule::in([
                'different_building', 'different_unit', 'different_area', 'different_boundary', 'different_address', 'other',
            ])],
            'difference_note' => ['required', 'string', 'min:10', 'max:500'],
        ]);

        $result = $this->identity->recordSelfVerification(
            $user,
            $property,
            (string) $validated['difference_type'],
            (string) $validated['difference_note'],
        );
        $this->audit->record($user, 'listing.identity_self_verified', $property, [
            'difference_type' => $validated['difference_type'],
            'result' => $result['status'] ?? $result['decision'],
        ], $request, $user->id);

        return response()->json(['data' => $result]);
    }

    public function transferRepresentation(Request $request, Property $property): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $validated = $request->validate(['reason' => ['required', 'string', 'min:10', 'max:500']]);
        $this->identity->transferRepresentation($actor, $property, (string) $validated['reason']);
        $this->audit->record($actor, 'property.representation_transferred', $property, [
            'property_asset_id' => $property->property_asset_id,
            'to_user_id' => $property->user_id,
            'reason' => $validated['reason'],
        ], $request, $property->user_id);
        return response()->json(['message' => 'تم نقل تمثيل العقار إلى المعلن الحالي.']);
    }

    private function assertOwner(Property $property, User $user): void
    {
        abort_unless((int) $property->user_id === (int) $user->id, 403);
    }
}
