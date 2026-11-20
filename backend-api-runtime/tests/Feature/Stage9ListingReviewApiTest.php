<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Models\UserNotificationPreference;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;
use Tests\Concerns\ConfirmsListingImages;

class Stage9ListingReviewApiTest extends TestCase
{
    use RefreshDatabase;
    use ConfirmsListingImages;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_new_listing_is_private_draft_until_review_approval(): void
    {
        [, $ownerHeaders] = $this->user('s9-owner@example.test', '+967710000001');
        [, $modHeaders] = $this->user('s9-mod@example.test', '+967710000002', ['support_agent']);

        $created = $this->withHeaders($ownerHeaders)->post('/api/properties', $this->payload([
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ]));
        $created->assertCreated()
            ->assertJsonPath('data.status', 'draft')
            ->assertJsonPath('data.review_status', 'draft');

        $id = (int) $created->json('data.id');
        $asset = (int) $created->json('data.property_asset_id');
        $this->assertGreaterThan(0, $asset);
        $imageId = (int) \DB::table('property_images')->where('property_id', $id)->value('id');
        $documentId = (int) \DB::table('listing_documents')->where('property_id', $id)->value('id');

        $this->withHeaders(['Authorization' => ''])->get("/api/property-media/$imageId")->assertNotFound();
        $this->withHeaders($modHeaders)->get("/api/property-media/$imageId")->assertOk();
        foreach ([$ownerHeaders, $modHeaders] as $authorizedHeaders) {
            foreach (['get', 'head'] as $method) {
                $response = $this->withHeaders($authorizedHeaders)
                    ->{$method}("/api/listing-documents/$documentId")
                    ->assertOk()
                    ->assertHeader('X-Content-Type-Options', 'nosniff');
                $cache = $response->headers->get('Cache-Control');
                $this->assertStringContainsString('private', $cache);
                $this->assertStringContainsString('no-store', $cache);
            }
        }
        [, $otherHeaders] = $this->user('s9-other@example.test', '+967710000003');
        $this->withHeaders($otherHeaders)->head("/api/listing-documents/$documentId")->assertForbidden();
        $this->withHeaders(['Authorization' => ''])->head("/api/listing-documents/$documentId")->assertUnauthorized();
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 0);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 0);

        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/start")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'under_review');
        $this->confirmListingImages($id, $modHeaders);
        $this->withHeaders($modHeaders)->postJson(
            "/api/admin/listing-review/listings/$id/approve",
            ['reason' => 'Verified proof and listing data.'],
        )->assertOk()
            ->assertJsonPath('data.status', 'published')
            ->assertJsonPath('data.review_status', 'approved');

        $this->getJson('/api/properties')->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.id', $id);
        $this->assertDatabaseHas('listing_reviews', ['listing_id' => $id, 'action' => 'approved']);
    }

    public function test_return_for_correction_keeps_reason_while_editing_and_can_be_resubmitted(): void
    {
        [, $ownerHeaders] = $this->user('s9-correct@example.test', '+967710000003');
        [, $modHeaders] = $this->user('s9-correct-mod@example.test', '+967710000004', ['content_moderator']);
        $id = $this->createReady($ownerHeaders, 'Correction property');

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($modHeaders)->postJson(
            "/api/admin/listing-review/listings/$id/return",
            ['reason' => 'Please clarify the address details.'],
        )->assertOk()->assertJsonPath('data.review_status', 'returned_for_correction');

        $this->assertDatabaseCount('property_publication_blocks', 0);
        $this->withHeaders($ownerHeaders)->postJson(
            "/api/properties/$id",
            ['address' => 'Clarified address'],
        )->assertOk()
            ->assertJsonPath('data.review_status', 'returned_for_correction')
            ->assertJsonPath('data.last_review_reason', 'Please clarify the address details.');

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
    }

    public function test_final_rejection_blocks_physical_property_for_same_purpose_across_accounts_only(): void
    {
        [, $a] = $this->user('s9-a@example.test', '+967710000005');
        [, $b] = $this->user('s9-b@example.test', '+967710000006');
        [, $mod] = $this->user('s9-reject-mod@example.test', '+967710000007', ['support_agent']);
        [, $manager] = $this->user('s9-manager@example.test', '+967710000008', ['support_manager']);

        $id = $this->createReady($a, 'Blocked property');
        $this->withHeaders($a)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->withHeaders($mod)->postJson(
            "/api/admin/listing-review/listings/$id/reject-final",
            ['reason' => 'Ownership evidence is invalid and property must be blocked.'],
        )->assertOk()->assertJsonPath('data.review_status', 'rejected_blocked');

        $this->assertDatabaseHas('property_publication_blocks', ['purpose' => 'sale', 'is_active' => 1]);
        $this->withHeaders($a)->deleteJson("/api/properties/$id")->assertStatus(409);
        $this->withHeaders($b)->postJson('/api/properties', $this->payload(['title' => 'Bypass attempt']))->assertStatus(409);
        $this->withHeaders($b)->postJson('/api/properties', $this->payload([
            'title' => 'Rent allowed',
            'purpose' => 'rent',
        ]))->assertCreated()->assertJsonPath('data.status', 'draft');

        $blockId = (int) \DB::table('property_publication_blocks')->where('is_active', true)->value('id');
        $this->withHeaders($mod)->postJson(
            "/api/admin/listing-review/blocks/$blockId/lift",
            ['reason' => 'Support manager approval after corrected property identity evidence.'],
        )->assertForbidden();
        $this->withHeaders($manager)->postJson(
            "/api/admin/listing-review/blocks/$blockId/lift",
            ['reason' => 'Support manager approval after corrected property identity evidence.'],
        )->assertOk()->assertJsonPath('data.is_active', false);
        $this->withHeaders($b)->postJson('/api/properties', $this->payload([
            'title' => 'Sale allowed after lift',
        ]))->assertCreated();
    }

    #[DataProvider('duplicateAdvertisers')]
    public function test_support_rejects_only_the_new_duplicate_and_notifies_its_advertiser(bool $sameOwner): void
    {
        [$owner, $ownerHeaders] = $this->user('s9-original@example.test', '+967710000016');
        [$advertiser, $advertiserHeaders] = $sameOwner
            ? [$owner, $ownerHeaders]
            : $this->user('s9-duplicate@example.test', '+967710000017');
        [, $mod] = $this->user('s9-duplicate-mod@example.test', '+967710000018', ['support_agent']);

        $previous = $this->createReady($ownerHeaders, 'Published original');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$previous/submit")->assertOk();
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$previous/start")->assertOk();
        $this->confirmListingImages($previous, $mod);
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$previous/approve")->assertOk();

        UserNotificationPreference::query()->create(['user_id' => $advertiser->id, 'listing_activity' => false]);
        $duplicate = $this->createReady($advertiserHeaders, 'New duplicate');
        $this->withHeaders($advertiserHeaders)->postJson("/api/properties/$duplicate/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $review = "/api/admin/listing-review/listings/$duplicate";
        $reason = 'أثبتت مراجعة العنوان والبيانات أنه نفس العقار.';
        $payload = ['candidate_property_id' => $previous, 'reason' => $reason];
        $this->withHeaders($advertiserHeaders)->postJson("$review/reject-duplicate", $payload)->assertForbidden();
        $this->withHeaders($mod)->postJson("$review/reject-duplicate", $payload)->assertConflict();
        $this->withHeaders($mod)->getJson($review)
            ->assertOk()
            ->assertJsonPath('data.duplicate_detection_source', 'algorithm')
            ->assertJsonPath('data.likely_duplicate_candidates.0.listing_id', $previous);
        $this->withHeaders($mod)->postJson("$review/start")->assertOk();
        $this->withHeaders($mod)->postJson("$review/reject-duplicate", ['candidate_property_id' => $duplicate] + $payload)->assertConflict();

        // The reference must remain accessible when support confirms the decision.
        \DB::table('properties')->where('id', $previous)->update(['availability_status' => 'sold']);
        $this->withHeaders($mod)->postJson("$review/reject-duplicate", $payload)->assertConflict();
        \DB::table('properties')->where('id', $previous)->update(['availability_status' => 'available']);

        $message = $sameOwner ? 'سبق نشره من قبلك. ' . $reason : $reason;
        $this->withHeaders($mod)->postJson("$review/reject-duplicate", $payload)->assertOk()
            ->assertJsonPath('data.status', 'rejected')
            ->assertJsonPath('data.review_status', 'rejected_duplicate')
            ->assertJsonPath('data.last_review_reason', $message);
        $this->withHeaders($mod)->postJson("$review/reject-duplicate", $payload)->assertConflict();
        $this->assertDatabaseCount('property_publication_blocks', 0);
        $this->assertDatabaseHas('listing_reviews', ['listing_id' => $duplicate, 'action' => 'rejected_duplicate']);
        $this->assertDatabaseHas('support_tasks', ['source_type' => 'listing_review', 'source_id' => $duplicate, 'status' => 'rejected']);

        $this->withHeaders($advertiserHeaders)->getJson('/api/notifications')->assertOk()
            ->assertJsonPath('data.0.type', 'listing_duplicate_rejected')
            ->assertJsonPath('data.0.entity_id', $duplicate)
            ->assertJsonPath('data.0.body', $message)
            ->assertJsonPath('data.0.data.previous_property_id', $previous)
            ->assertJsonPath('data.0.data.previous_listing_same_owner', $sameOwner);
        $this->assertSame(1, \DB::table('user_notifications')->where('type', 'listing_duplicate_rejected')->count());
        $this->withHeaders($advertiserHeaders)->getJson("/api/properties/$duplicate")->assertOk()
            ->assertJsonPath('data.can_edit', false)
            ->assertJsonPath('data.can_submit', false);
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$previous")->assertOk();
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$duplicate")->assertNotFound();
    }

    public static function duplicateAdvertisers(): array
    {
        return ['same account' => [true], 'different accounts' => [false]];
    }

    public function test_published_edit_moves_back_to_draft_and_unpublishes_until_reapproval(): void
    {
        [, $owner] = $this->user('s9-edit@example.test', '+967710000009');
        [, $mod] = $this->user('s9-edit-mod@example.test', '+967710000010', ['support_agent']);
        $id = $this->createReady($owner, 'Published edit');
        $this->withHeaders($owner)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->confirmListingImages($id, $mod);
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$id/approve")->assertOk();
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 1);

        $this->withHeaders($owner)->postJson("/api/properties/$id", ['price' => 62000000])
            ->assertOk()
            ->assertJsonPath('data.status', 'draft')
            ->assertJsonPath('data.review_status', 'draft');
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 0);
    }

    public function test_listing_review_history_is_immutable(): void
    {
        [, $owner] = $this->user('s9-immutable@example.test', '+967710000011');
        $id = $this->createReady($owner, 'Immutable review');
        $this->withHeaders($owner)->postJson("/api/properties/$id/submit")->assertOk();
        $reviewId = (int) \DB::table('listing_reviews')->where('listing_id', $id)->value('id');

        $failed = false;
        try {
            \DB::table('listing_reviews')->where('id', $reviewId)->update(['reason' => 'tamper']);
        } catch (\Throwable) {
            $failed = true;
        }
        $this->assertTrue($failed, 'listing_reviews must reject mutation');
    }

    public function test_review_actor_history_survives_reviewer_account_deletion(): void
    {
        [, $owner] = $this->user('s9-history-owner@example.test', '+967710000012');
        [$moderator, $modHeaders] = $this->user('s9-history-mod@example.test', '+967710000013', ['support_agent']);
        $id = $this->createReady($owner, 'Reviewer history');
        $this->withHeaders($owner)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
        $this->confirmListingImages($id, $modHeaders);
        $this->withHeaders($modHeaders)->postJson(
            "/api/admin/listing-review/listings/$id/approve",
            ['reason' => 'Reviewer history snapshot test.'],
        )->assertOk();

        $review = \DB::table('listing_reviews')
            ->where('listing_id', $id)
            ->where('action', 'approved')
            ->first();
        $this->assertNotNull($review);
        $this->assertSame($moderator->id, (int) $review->actor_user_id);
        $this->assertSame($moderator->name, $review->actor_name_snapshot);

        User::query()->whereKey($moderator->id)->delete();

        $after = \DB::table('listing_reviews')->where('id', $review->id)->first();
        $this->assertNotNull($after);
        $this->assertSame($moderator->id, (int) $after->actor_user_id);
        $this->assertSame($moderator->name, $after->actor_name_snapshot);
    }

    private function createReady(array $headers, string $title): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', $this->payload([
            'title' => $title,
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ]));
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'Stage 9 User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make(hash('sha256', $email . '|stage9')),
        ]);
        $ids = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $ids[$role->id] = ['assigned_by_user_id' => null, 'created_at' => now()];
        }
        $user->roles()->sync($ids);
        $plain = 're9_' . substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'stage9-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer ' . $plain, 'Accept' => 'application/json']];
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title' => 'Stage 9 property',
            'description' => 'Review workflow property',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 60000000,
            'currency' => 'YER',
            'area_m2' => 230,
            'bedrooms' => 4,
            'bathrooms' => 3,
            'address' => 'Stage 9 Identity Address',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ], $overrides);
    }
}
