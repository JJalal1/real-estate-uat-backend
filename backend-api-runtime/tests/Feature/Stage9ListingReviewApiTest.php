<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Stage9ListingReviewApiTest extends TestCase
{
    use RefreshDatabase;

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
        $this->withHeaders($modHeaders)->get("/api/listing-documents/$documentId")->assertOk();
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 0);

        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
        $this->getJson('/api/properties')->assertJsonPath('meta.total', 0);

        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/start")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'under_review');
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

    public function test_published_edit_moves_back_to_draft_and_unpublishes_until_reapproval(): void
    {
        [, $owner] = $this->user('s9-edit@example.test', '+967710000009');
        [, $mod] = $this->user('s9-edit-mod@example.test', '+967710000010', ['support_agent']);
        $id = $this->createReady($owner, 'Published edit');
        $this->withHeaders($owner)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($mod)->postJson("/api/admin/listing-review/listings/$id/start")->assertOk();
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


    public function test_video_requires_processing_and_explicit_staff_confirmation_to_publish(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        [, $ownerHeaders] = $this->user('s9-video-owner@example.test', '+967710000035');
        [$moderator, $modHeaders] = $this->user('s9-video-mod@example.test', '+967710000036', ['support_agent']);
        $id = $this->createReady($ownerHeaders, 'Video approval listing');
        $playback = 'listing-video-display/approval/safe.mp4';
        $poster = 'listing-video-display/approval/poster.jpg';
        Storage::disk('local')->put($playback, '0123456789ABCDEFGHIJ');
        Storage::disk('local')->put($poster, 'jpeg-test');
        $video = \App\Models\ListingVideo::query()->create([
            'property_id' => $id,
            'upload_id' => (string) \Illuminate\Support\Str::uuid(),
            'status' => 'uploaded',
            'original_path' => 'listing-videos/approval/original.mp4',
            'mime_type' => 'video/mp4',
            'size_bytes' => 20,
            'content_sha256' => str_repeat('a', 64),
        ]);
        // Submitting an incomplete video must fail closed.
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertStatus(409);
        $video->forceFill([
            'status' => 'ready', 'playback_path' => $playback,
            'poster_path' => $poster, 'playback_size_bytes' => 20,
        ])->save();
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")->assertOk();
        $this->withHeaders($modHeaders)->getJson("/api/admin/listing-review/listings/$id")
            ->assertOk()
            ->assertJsonPath('data.video.id', $video->id)
            ->assertJsonPath('data.video.status', 'ready')
            ->assertJsonPath('data.video.moderation_status', 'pending');
        $this->withHeaders($modHeaders)->get("/api/property-videos/{$video->id}/stream")
            ->assertStatus(206);
        $this->withHeaders(['Authorization' => ''])
            ->get("/api/property-videos/{$video->id}/stream")->assertNotFound();
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/start")
            ->assertOk();
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/approve")
            ->assertStatus(409);
        $this->assertDatabaseHas('listing_videos', ['id' => $video->id, 'moderation_status' => 'pending']);
        $this->withHeaders($modHeaders)->postJson("/api/admin/listing-review/listings/$id/approve", [
            'video_review_confirmed' => true,
            'reason' => 'Watched and confirmed this video.',
        ])->assertOk()->assertJsonPath('data.review_status', 'approved');
        $this->assertDatabaseHas('listing_videos', [
            'id' => $video->id,
            'moderation_status' => 'approved',
            'moderated_by_user_id' => $moderator->id,
        ]);
        $this->withHeaders(['Authorization' => ''])->getJson("/api/properties/$id")
            ->assertOk()->assertJsonPath('data.video.id', $video->id);
        $this->withHeaders(['Authorization' => ''])
            ->get("/api/property-videos/{$video->id}/stream")->assertStatus(206);
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
