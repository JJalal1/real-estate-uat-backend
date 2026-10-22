<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class AccountErasureService
{
    public function __construct(
        private readonly CloudAssetStorageService $storage,
        private readonly AuditLogService $audit,
    ) {}

    public function erase(User $user, Request $request): array
    {
        $staffRoles = [
            'super_admin',
            'platform_admin',
            'permissions_manager',
            'support_manager',
            'support_agent',
            'regions_manager',
            'content_moderator',
        ];
        if ($user->is_platform_owner || $user->roles()->whereIn('key', $staffRoles)->exists()) {
            throw new ConflictHttpException('يجب نقل مهام وصلاحيات حساب الموظف قبل حذفه.');
        }

        $verificationPaths = $this->verificationPaths($user);
        $professionalPhoto = trim((string) ($user->public_professional_photo_path ?? ''));
        $videoPaths = $this->listingVideoPaths($user);

        foreach ($videoPaths as $path) {
            $this->storage->deletePrivate($path);
        }

        foreach ($verificationPaths as $path) {
            $this->storage->deletePrivate($path);
        }
        if ($professionalPhoto !== '') {
            $this->storage->deletePublic($professionalPhoto);
            $this->storage->deletePrivate($professionalPhoto);
        }

        $anonymizedEmail = sprintf(
            'deleted-%d-%s@deleted.invalid',
            $user->id,
            Str::lower(Str::random(16)),
        );

        DB::transaction(function () use ($user, $request, $anonymizedEmail): void {
            $locked = User::query()->lockForUpdate()->findOrFail($user->id);
            if ($locked->account_status === User::STATUS_DELETED) return;

            $this->archiveListings($locked);
            $this->deleteTransientData($locked);
            if (Schema::hasTable('listing_videos')) {
                DB::table('listing_videos')->whereIn('property_id',
                    DB::table('properties')->where('user_id', $locked->id)->select('id'))->delete();
            }

            if (Schema::hasTable('account_verification_profiles')) {
                DB::table('account_verification_profiles')->where('user_id', $locked->id)->delete();
            }
            if (Schema::hasTable('broker_verification_documents')) {
                DB::table('broker_verification_documents')->where('user_id', $locked->id)->delete();
            }

            DB::table('user_role')->where('user_id', $locked->id)->delete();
            DB::table('user_permission_overrides')->where('user_id', $locked->id)->delete();

            $locked->forceFill([
                'name' => 'مستخدم محذوف',
                'email' => $anonymizedEmail,
                'email_verified_at' => null,
                'phone' => null,
                'phone_verified_at' => null,
                'password' => Hash::make(Str::random(96)),
                'remember_token' => null,
                'account_type' => User::ACCOUNT_TYPE_REGULAR,
                'identity_policy_version' => 0,
                'account_status' => User::STATUS_DELETED,
                'last_login_at' => null,
                'profile_completed_at' => null,
                'broker_verification_status' => User::BROKER_VERIFICATION_NOT_REQUIRED,
                'broker_verification_submitted_at' => null,
                'broker_verified_at' => null,
                'broker_verified_by_user_id' => null,
                'broker_verification_note' => null,
                'public_professional_bio' => null,
                'public_professional_photo_path' => null,
            ])->save();

            $this->audit->record(
                $locked,
                'account.erased',
                $locked,
                ['retained_records' => ['financial', 'contracts', 'audit', 'shared_messages']],
                $request,
                $locked->id,
            );
        });

        return [
            'account_deleted' => true,
            'access_revoked' => true,
            'personal_identity_erased' => true,
            'public_listings_archived' => true,
            'retained_for_integrity' => ['financial_records', 'contracts', 'audit_history', 'shared_messages'],
        ];
    }

    private function verificationPaths(User $user): array
    {
        $paths = [];
        if (Schema::hasTable('account_verification_profiles')) {
            $profileId = DB::table('account_verification_profiles')->where('user_id', $user->id)->value('id');
            if ($profileId && Schema::hasTable('account_verification_documents')) {
                $paths = array_merge($paths, DB::table('account_verification_documents')
                    ->where('profile_id', $profileId)->pluck('path')->filter()->all());
            }
        }
        if (Schema::hasTable('broker_verification_documents')) {
            $paths = array_merge($paths, DB::table('broker_verification_documents')
                ->where('user_id', $user->id)->pluck('path')->filter()->all());
        }
        return array_values(array_unique(array_filter($paths, 'is_string')));
    }

    /** Delete media originals and derivatives; retain financial/legal listing records. */
    private function listingVideoPaths(User $user): array
    {
        if (! Schema::hasTable('listing_videos')) return [];
        $records = DB::table('listing_videos')
            ->join('properties', 'properties.id', '=', 'listing_videos.property_id')
            ->where('properties.user_id', $user->id)
            ->get(['listing_videos.original_path', 'listing_videos.playback_path', 'listing_videos.poster_path']);
        $paths = [];
        foreach ($records as $video) {
            foreach ([$video->original_path, $video->playback_path, $video->poster_path] as $path) {
                if (is_string($path) && $path !== '') $paths[] = $path;
            }
        }
        return array_values(array_unique($paths));
    }

    private function archiveListings(User $user): void
    {
        if (! Schema::hasTable('properties')) return;
        DB::table('properties')->where('user_id', $user->id)->update([
            'status' => 'archived',
            'contact_phone' => null,
            'contact_whatsapp' => null,
            'ownership_document_type' => null,
            'document_owner_name' => null,
            'owner_relationship_type' => null,
            'owner_relationship_note' => null,
            'updated_at' => now(),
        ]);
    }

    private function deleteTransientData(User $user): void
    {
        $simple = [
            'api_tokens' => ['user_id'],
            'sessions' => ['user_id'],
            'verification_challenges' => ['user_id'],
            'listing_editor_drafts' => ['user_id'],
            'property_favorites' => ['user_id'],
            'saved_property_searches' => ['user_id'],
            'user_notifications' => ['user_id'],
            'user_notification_preferences' => ['user_id'],
            'user_push_devices' => ['user_id'],
            'broker_customer_followups' => ['user_id'],
            'support_team_members' => ['user_id'],
        ];

        foreach ($simple as $table => $columns) {
            if (! Schema::hasTable($table)) continue;
            $query = DB::table($table);
            foreach ($columns as $column) $query->where($column, $user->id);
            $query->delete();
        }

        if (Schema::hasTable('user_messaging_blocks')) {
            DB::table('user_messaging_blocks')
                ->where('user_id', $user->id)
                ->orWhere('blocked_user_id', $user->id)
                ->delete();
        }
        if (Schema::hasTable('listing_comments')) {
            DB::table('listing_comments')->where('author_user_id', $user->id)->delete();
        }
        if (Schema::hasTable('advertiser_ratings')) {
            DB::table('advertiser_ratings')->where('rater_user_id', $user->id)->delete();
        }
        if (Schema::hasTable('password_reset_tokens')) {
            DB::table('password_reset_tokens')->where('email', $user->email)->delete();
        }
    }
}
