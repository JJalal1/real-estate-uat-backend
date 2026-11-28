<?php

namespace App\Http\Controllers\Concerns;

use App\Models\AccountVerificationProfile;
use App\Models\User;

trait SerializesSessionUser
{
    private function userData(User $user): array
    {
        $user->loadMissing(['roles','permissionOverrides.permission','accountVerificationProfile.documents']);
        return [
            'id'=>(int)$user->id,
            'name'=>$user->name,
            'email'=>$user->email,
            'phone'=>$user->phone,
            'public_bio'=>$user->public_professional_bio,
            'account_type'=>$user->account_type ?? User::ACCOUNT_TYPE_REGULAR,
            'phone_verified_at'=>$user->phone_verified_at?->toIso8601String(),
            'email_verified_at'=>$user->email_verified_at?->toIso8601String(),
            'profile_completed_at'=>$user->profile_completed_at?->toIso8601String(),
            'account_status'=>$user->account_status,
            'broker_verification_status'=>$user->broker_verification_status ?? User::BROKER_VERIFICATION_NOT_REQUIRED,
            'broker_verification_submitted_at'=>$user->broker_verification_submitted_at?->toIso8601String(),
            'broker_verified_at'=>$user->broker_verified_at?->toIso8601String(),
            'broker_enrolled'=>$user->broker_enrolled_at !== null,
            'marketplace_is_office'=>$user->marketplace_is_office === null ? null : (bool) $user->marketplace_is_office,
            'can_create_listing'=>$user->canCreateListings(),
            'can_manage_existing_listings'=>$user->canManageExistingListings(),
            'publication_hold_case_id'=>$user->support_publication_hold_case_id,
            'broker_verification_note'=>$user->broker_verification_note,
            'last_login_at'=>$user->last_login_at?->toIso8601String(),
            'created_at'=>$user->created_at?->toIso8601String(),
            'is_platform_owner'=>(bool)$user->is_platform_owner,
            'verification_profile'=>$this->verificationProfileData($user),
            'roles'=>$user->roleKeys(),
            'permissions'=>$user->effectivePermissionKeys(),
        ];
    }

    private function verificationProfileData(User $user): array
    {
        $profile=$user->accountVerificationProfile;
        if(!$profile || $profile->type === AccountVerificationProfile::TYPE_OWNER){
            return [
                'type'=>null,
                'status'=>'not_submitted',
                'submitted_at'=>null,
                'reviewed_at'=>null,
                'note'=>null,
                'flags'=>[
                    'identity_reviewed'=>false,
                    'professional_document_reviewed'=>false,
                    'commercial_register_reviewed'=>false,
                    'office_documents_reviewed'=>false,
                    'office_location_registered'=>false,
                ],
            ];
        }
        $kinds=$profile->documents->pluck('kind');
        $approved=$profile->isApproved();
        return [
            'type'=>$profile->type,
            'status'=>$profile->status,
            'submitted_at'=>$profile->submitted_at?->toIso8601String(),
            'reviewed_at'=>$profile->reviewed_at?->toIso8601String(),
            'note'=>$profile->review_note,
            'flags'=>[
                'identity_reviewed'=>$approved,
                'professional_document_reviewed'=>$approved && $profile->type==='broker' && $kinds->contains('professional_license'),
                'commercial_register_reviewed'=>$approved && $profile->type==='office' && $kinds->contains('commercial_register'),
                'office_documents_reviewed'=>$approved && $profile->type==='office' && $kinds->contains('office_license'),
                'office_location_registered'=>$approved && $profile->type==='office' && isset(($profile->details ?? [])['latitude'],($profile->details ?? [])['longitude']),
            ],
        ];
    }
}
