<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AccountVerificationProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FreeServicesHubController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        $profile = AccountVerificationProfile::query()
            ->where('user_id', $user->id)
            ->first();

        $professionalProfile = $profile?->type === AccountVerificationProfile::TYPE_OWNER ? null : $profile;
        $profileType = $professionalProfile?->type;
        $verificationStatus = $professionalProfile?->status ?? AccountVerificationProfile::STATUS_NOT_SUBMITTED;
        $verifiedProfessional = $professionalProfile?->isApproved() === true;

        return response()->json([
            'data' => [
                'ui_version' => 'free_services_v2',
                'pricing_model' => 'free',
                'paid_features_enabled' => false,
                'account_type' => $user->broker_enrolled_at ? 'broker' : ($profileType ?? 'basic'),
                'verification_status' => $verificationStatus,
                'verified_professional' => $verifiedProfessional,
                'capabilities' => [
                    'create_listing' => $user->canCreateListings(),
                    'view_my_listings' => true,
                    'rental_contracts' => $profile?->isApproved() === true,
                    'price_indicators' => true,
                    'property_valuation' => true,
                    'real_estate_guide' => true,
                    'legal_library' => true,
                ],
                // Availability is server-driven. A planned service becomes
                // available only after its persistence, API, authorization,
                // Flutter flow, and regression coverage are complete.
                'availability' => [
                    'create_listing' => $user->canCreateListings() ? 'available' : 'requires_profile',
                    'my_listings' => 'available',
                    'rental_contracts' => 'planned',
                    'price_indicators' => 'planned',
                    'property_valuation' => 'planned',
                    'real_estate_guide' => 'planned',
                    'legal_library' => 'planned',
                ],
            ],
        ]);
    }
}
