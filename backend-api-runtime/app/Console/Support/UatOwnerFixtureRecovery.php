<?php

namespace App\Console\Support;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/** Read-only recovery of the exact empty consumer created by the audited v1. */
class UatOwnerFixtureRecovery
{
    public const PHONE='+12025550149';
    public const EMAIL='uat-owner-erasure-20261026@example.invalid';
    public const NAME='حساب اصطناعي لاختبار الحذف';
    public const PREVIOUS='2026-10-26-owner-v1';

    public function find(): ?User
    {
        $rows=User::where('email',self::EMAIL)->orWhere('phone',self::PHONE)->get();
        if ($rows->isEmpty()) return null;
        if ($rows->count()!==1) throw new RuntimeException('fixture_collision');
        $user=$rows->first();
        $created=AuditLog::where('action','uat.owner_acceptance.fixture_created')->where('subject_type','User')
            ->where('subject_id',$user->id)->where('metadata->release_run',self::PREVIOUS)->where('metadata->fixture','erasure')->exists();
        $previous=AuditLog::where('action','uat.owner_acceptance.finished')->where('metadata->release_run',self::PREVIOUS)->latest('id')->first();
        $result=$previous?->metadata['result'] ?? [];
        $throttled=collect($result['cases'] ?? [])->contains(fn ($case) => ($case['case'] ?? null)==='otp_start_reviewer'
            && ($case['status'] ?? null)===429 && ($case['passed'] ?? null)===false);
        if (!$created || !$throttled || ($result['status'] ?? null)!=='incomplete' || ($result['probe_sessions_revoked'] ?? null)!==true
            || $user->email!==self::EMAIL || $user->phone!==self::PHONE || $user->name!==self::NAME
            || !$user->isActive() || $user->account_type!=='regular' || !$user->phone_verified_at || !$user->profile_completed_at
            || (int)$user->identity_policy_version!==2 || $user->roles()->pluck('key')->all()!==['registered_user']
            || $user->apiTokens()->exists() || DB::table('properties')->where('user_id',$user->id)->exists()
            || DB::table('listing_editor_drafts')->where('user_id',$user->id)->exists()
            || DB::table('message_thread_participants')->where('user_id',$user->id)->exists()
            || DB::table('property_agreements')->where('requester_user_id',$user->id)->orWhere('advertiser_user_id',$user->id)->exists()) {
            throw new RuntimeException('fixture_collision');
        }
        return $user;
    }
}
