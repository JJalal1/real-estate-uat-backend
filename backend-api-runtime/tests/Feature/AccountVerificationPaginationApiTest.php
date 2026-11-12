<?php

namespace Tests\Feature;

use App\Models\AccountVerificationDocument;
use App\Models\AccountVerificationProfile;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Models\UserPermissionOverride;
use App\Services\AccessControlService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class AccountVerificationPaginationApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_default_page_preserves_100_row_cap_fields_and_deterministic_order_and_exposes_page_two(): void
    {
        [, $headers] = $this->actor(['support_agent']);
        $this->seedLongQueue();

        $first = $this->withHeaders($headers)->getJson('/api/admin/account-verifications')
            ->assertOk()->assertJsonCount(100, 'data')
            ->assertJsonPath('meta', ['current_page' => 1, 'last_page' => 2, 'per_page' => 100, 'total' => 101]);
        // Every timestamp is tied, so the existing profile-ID tie-breaker matters.
        $this->assertSame(range(201, 102), array_column($first->json('data'), 'user_id'));
        $first->assertJsonStructure(['data' => ['*' => [
            'user_id', 'name', 'phone', 'type', 'status', 'details',
            'submitted_at', 'reviewed_at', 'note', 'documents', 'verification_flags',
        ]]])->assertJsonPath('data.0.name', 'Synthetic profile 201')
            ->assertJsonPath('data.0.details.governorate', 'صنعاء')
            ->assertJsonPath('data.0.documents.0.original_name', 'identity-201.jpg')
            ->assertJsonPath('data.0.documents.0.url', '/api/account-verification/users/201/documents/identity_document')
            ->assertJsonPath('data.0.verification_flags.identity_reviewed', false)
            ->assertJsonMissingPath('data.0.documents.0.path');
        $this->assertStringNotContainsString('private/synthetic-verification/', $first->getContent());

        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?page=2')
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.user_id', 101)
            ->assertJsonPath('meta', ['current_page' => 2, 'last_page' => 2, 'per_page' => 100, 'total' => 101]);
        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?page=3')
            ->assertOk()->assertJsonPath('data', [])
            ->assertJsonPath('meta.current_page', 3)->assertJsonPath('meta.total', 101);
    }

    public function test_exact_user_101_outside_first_page_loads_only_its_profile_and_document_metadata(): void
    {
        [, $headers] = $this->actor(['support_agent']);
        $this->seedLongQueue();
        $loadedDocuments = [];
        AccountVerificationDocument::retrieved(function (AccountVerificationDocument $document) use (&$loadedDocuments): void {
            $loadedDocuments[] = $document->original_name;
        });

        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?user_id=101&per_page=1')
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.user_id', 101)
            ->assertJsonPath('data.0.documents.0.original_name', 'identity-101.jpg')
            ->assertJsonPath('meta', ['current_page' => 1, 'last_page' => 1, 'per_page' => 1, 'total' => 1]);
        $this->assertSame(['identity-101.jpg'], $loadedDocuments);
    }

    public function test_user_filter_composes_with_status_type_and_page_without_revealing_nonexistent_users(): void
    {
        [$actor, $headers] = $this->actor(['support_agent']);
        $this->profile(101, 'pending', 'owner');
        $this->profile(102, 'pending', 'broker')
            ->forceFill(['submitted_at' => '2026-10-31 12:00:00'])->save();
        $this->profile(103, 'approved', 'owner');
        $this->profile(104, 'approved', 'owner');

        // A newer submission wins even when an older row has a higher ID.
        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?per_page=1')
            ->assertOk()->assertJsonPath('data.0.user_id', 101)->assertJsonPath('meta.total', 2);
        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?status=approved&type=owner&page=2&per_page=1')
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.user_id', 103)
            ->assertJsonPath('meta', ['current_page' => 2, 'last_page' => 2, 'per_page' => 1, 'total' => 2]);
        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?user_id=102&status=pending&type=broker')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.user_id', 102);
        foreach ([
            'user_id=999999',
            'user_id='.$actor->id,
            'user_id=101&type=broker',
            'user_id=101&status=approved',
        ] as $query) {
            $this->withHeaders($headers)->getJson('/api/admin/account-verifications?'.$query)
                ->assertOk()->assertJsonPath('data', [])
                ->assertJsonPath('meta', ['current_page' => 1, 'last_page' => 1, 'per_page' => 100, 'total' => 0]);
        }
    }

    public function test_paging_and_exact_user_filters_validate_without_mutating_profiles(): void
    {
        [, $headers] = $this->actor(['support_agent']);
        $profile = $this->profile(101);
        $before = $profile->fresh()->getAttributes();
        foreach ([
            ['user_id', '0'], ['user_id', '-1'], ['user_id', '1.5'], ['user_id', 'abc'],
            ['page', '0'], ['page', '-1'], ['page', '1.5'], ['page', 'abc'],
            ['per_page', '0'], ['per_page', '-1'], ['per_page', '101'], ['per_page', '1.5'],
            ['status', 'unknown'], ['type', 'unknown'],
        ] as [$field, $value]) {
            $this->withHeaders($headers)->getJson('/api/admin/account-verifications?'.http_build_query([$field => $value]))
                ->assertUnprocessable()->assertJsonValidationErrors($field);
        }
        $this->assertSame($before, $profile->fresh()->getAttributes());
    }

    public function test_authentication_and_existing_role_permissions_still_guard_all_pages_and_exact_user_queries(): void
    {
        $this->profile(101);
        $this->getJson('/api/admin/account-verifications?page=2&user_id=101')->assertUnauthorized();
        $this->getJson('/api/admin/account-verifications?user_id=0&per_page=0')->assertUnauthorized();
        $rolePermissions = $this->rolePermissions();

        foreach ([
            [[], false], [['content_moderator'], false], [['support_agent'], true],
            [['support_manager'], true], [['platform_admin'], true],
        ] as [$roles, $allowed]) {
            [$actor, $headers] = $this->actor($roles);
            $beforeRoles = $actor->roleKeys();
            $beforePermissions = $actor->effectivePermissionKeys();
            $response = $this->withHeaders($headers)
                ->getJson('/api/admin/account-verifications?user_id=101&per_page=1');
            if ($allowed) {
                $response->assertOk()->assertJsonPath('data.0.user_id', 101);
            } else {
                $response->assertForbidden()->assertJsonMissingPath('data');
                $this->withHeaders($headers)->getJson('/api/admin/account-verifications?user_id=0&per_page=0')
                    ->assertForbidden();
            }
            $this->assertSame($beforeRoles, $actor->fresh()->roleKeys());
            $this->assertSame($beforePermissions, $actor->fresh()->effectivePermissionKeys());
        }
        $this->assertSame($rolePermissions, $this->rolePermissions());
    }

    public function test_explicit_permission_denial_still_overrides_the_support_role_on_exact_user_lookup(): void
    {
        $this->profile(101);
        [$actor, $headers] = $this->actor(['support_agent']);
        UserPermissionOverride::query()->create([
            'user_id' => $actor->id,
            'permission_id' => Permission::query()->where('key', 'accounts.verify_profiles')->firstOrFail()->id,
            'effect' => 'deny', 'assigned_by_user_id' => $actor->id,
            'reason' => 'Synthetic permission boundary test',
        ]);
        $this->withHeaders($headers)->getJson('/api/admin/account-verifications?user_id=101&page=1&per_page=1')
            ->assertForbidden()->assertJsonMissingPath('data');
    }

    private function seedLongQueue(): void
    {
        for ($id = 101; $id <= 201; $id++) $this->profile($id);
    }

    private function profile(int $userId, string $status = 'pending', string $type = 'owner'): AccountVerificationProfile
    {
        User::factory()->create([
            'id' => $userId, 'name' => 'Synthetic profile '.$userId,
            'phone' => '+967755'.str_pad((string) $userId, 6, '0', STR_PAD_LEFT),
            'phone_verified_at' => now(), 'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
        ]);
        $profile = AccountVerificationProfile::query()->create([
            'user_id' => $userId, 'type' => $type, 'status' => $status,
            'details' => ['governorate' => 'صنعاء', 'district' => 'السبعين'],
            'submitted_at' => '2026-11-01 12:00:00',
            'reviewed_at' => $status === 'approved' ? '2026-11-02 12:00:00' : null,
        ]);
        $profile->documents()->create([
            'kind' => 'identity_document', 'path' => 'private/synthetic-verification/'.$userId.'.jpg',
            'original_name' => 'identity-'.$userId.'.jpg', 'mime_type' => 'image/jpeg', 'size_bytes' => 120,
        ]);
        return $profile;
    }

    private function actor(array $roles): array
    {
        $user = User::factory()->create([
            'phone_verified_at' => now(), 'profile_completed_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
        ]);
        app(AccessControlService::class)->ensureRegisteredUser($user);
        foreach ($roles as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $user->roles()->syncWithoutDetaching([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
        }
        $plain = 'synthetic_verification_pages_'.$user->id;
        $user->apiTokens()->create([
            'name' => 'verification-pagination-test', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour(),
        ]);
        return [$user->fresh(), ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }

    private function rolePermissions(): array
    {
        return DB::table('role_permission')->orderBy('role_id')->orderBy('permission_id')->get()
            ->map(fn ($row) => (array) $row)->all();
    }
}
