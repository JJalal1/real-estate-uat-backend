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

        $profileType = $profile?->type;
        $verificationStatus = $profile?->status ?? AccountVerificationProfile::STATUS_NOT_SUBMITTED;
        $verifiedProfessional = $profile !== null
            && $profile->isApproved()
            && in_array($profileType, [
                AccountVerificationProfile::TYPE_OWNER,
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ], true);
        $verifiedBrokerOrOffice = $verifiedProfessional
            && in_array($profileType, [
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ], true);

        return response()->json([
            'data' => [
                'ui_version' => 'free_services_v1',
                'pricing_model' => 'free',
                'paid_features_enabled' => false,
                'account_type' => $profileType ?? 'basic',
                'verification_status' => $verificationStatus,
                'verified_professional' => $verifiedProfessional,
                'capabilities' => [
                    'create_listing' => $verifiedProfessional,
                    'view_my_listings' => true,
                    'create_property_request' => true,
                    'view_property_requests' => true,
                    'view_researcher_requests' => $verifiedBrokerOrOffice,
                    'rental_contracts' => $verifiedProfessional,
                    'price_indicators' => true,
                    'property_valuation' => true,
                    'real_estate_guide' => true,
                    'legal_library' => true,
                ],
                // Availability is deliberately server-driven. Later workflow packages
                // flip each code to "available" only after its API and persistence are live.
                'availability' => [
                    'create_listing' => $verifiedProfessional ? 'available' : 'requires_verification',
                    'my_listings' => 'available',
                    'property_requests' => 'available',
                    'researcher_requests' => $verifiedBrokerOrOffice ? 'available' : 'requires_verification',
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
