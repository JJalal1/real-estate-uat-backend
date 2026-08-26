<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatChangePhase1ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_phase1_comment_reports_and_direct_advertiser_messaging_work_together(): void
    {
        [$advertiser, $advertiserHeaders] = $this->user(
            'phase1-advertiser@example.test',
            '+967760000001',
        );
        [$viewer, $viewerHeaders] = $this->user(
            'phase1-viewer@example.test',
            '+967760000002',
        );
        $listing = $this->publishedListing($advertiser, 'Phase 1 published listing');

        $comment = $this->withHeaders($viewerHeaders)->postJson(
            "/api/properties/{$listing->id}/comments",
            ['body' => 'تعليق اختبار للمرحلة الأولى.'],
        );
        $comment->assertCreated()
            ->assertJsonPath('data.author_user_id', $viewer->id)
            ->assertJsonPath('data.is_owner', true)
            ->assertJsonPath('data.status', 'visible');

        $listingReport = $this->withHeaders($viewerHeaders)->postJson('/api/reports', [
            'target_type' => 'listing',
            'target_id' => $listing->id,
            'reason' => 'misleading',
            'details' => 'تفاصيل كافية لاختبار بلاغ الإعلان في المرحلة الأولى.',
        ]);
        $listingReport->assertCreated()
            ->assertJsonPath('data.kind', 'report')
            ->assertJsonPath('data.target_type', 'listing')
            ->assertJsonPath('data.status', 'open');

        $this->withHeaders($viewerHeaders)->postJson('/api/reports', [
            'target_type' => 'listing',
            'target_id' => $listing->id,
            'reason' => 'misleading',
            'details' => 'محاولة تكرار البلاغ يجب أن تعاد كتعارض واضح.',
        ])->assertStatus(409);

        $advertiserReport = $this->withHeaders($viewerHeaders)->postJson('/api/reports', [
            'target_type' => 'advertiser',
            'target_id' => $advertiser->id,
            'reason' => 'other',
            'details' => 'تفاصيل كافية لاختبار بلاغ المعلن بصورة مستقلة.',
        ]);
        $advertiserReport->assertCreated()
            ->assertJsonPath('data.target_type', 'advertiser');

        $conversation = $this->withHeaders($viewerHeaders)->postJson(
            "/api/properties/{$listing->id}/conversation",
        );
        $conversation->assertCreated()
            ->assertJsonPath('data.other_user.id', $advertiser->id);
        $threadId = (int) $conversation->json('data.id');

        $sameConversation = $this->withHeaders($viewerHeaders)->postJson(
            "/api/properties/{$listing->id}/conversation",
        );
        $sameConversation->assertOk()->assertJsonPath('data.id', $threadId);

        $this->withHeaders($viewerHeaders)->postJson(
            "/api/messages/threads/{$threadId}/messages",
            ['body' => 'هل ما زال العقار متاحاً؟'],
        )->assertCreated();

        $this->withHeaders($advertiserHeaders)->getJson('/api/messages/threads')
            ->assertOk()
            ->assertJsonPath('data.0.id', $threadId)
            ->assertJsonPath('data.0.other_user.id', $viewer->id)
            ->assertJsonPath('data.0.unread_count', 1);

        $this->withHeaders($advertiserHeaders)->postJson(
            "/api/properties/{$listing->id}/conversation",
        )->assertUnprocessable();
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Phase 1 User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $role = Role::query()->where('key', 'registered_user')->firstOrFail();
        $user->roles()->sync([
            $role->id => [
                'assigned_by_user_id' => null,
                'created_at' => now(),
            ],
        ]);
        $plain = 'phase1_'.substr(hash('sha512', $email), 0, 76);
        $user->apiTokens()->create([
            'name' => 'phase1-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function publishedListing(User $advertiser, string $title): Property
    {
        $asset = PropertyAsset::query()->create([
            'created_by_user_id' => $advertiser->id,
            'identity_hash' => hash('sha256', $advertiser->email.'|'.$title),
            'identity_version' => 1,
            'property_type' => 'house',
            'canonical_address' => 'Phase 1 Address',
            'canonical_latitude' => 15.3694,
            'canonical_longitude' => 44.1910,
            'area_m2' => 220,
            'bedrooms' => 4,
            'bathrooms' => 3,
            'status' => 'active',
        ]);

        return Property::query()->create([
            'user_id' => $advertiser->id,
            'property_asset_id' => $asset->id,
            'owner_key' => null,
            'title' => $title,
            'description' => 'Phase 1 published listing',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 55000000,
            'currency' => 'YER',
            'area_m2' => 220,
            'bedrooms' => 4,
            'bathrooms' => 3,
            'address' => 'Phase 1 Address',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'published_at' => now(),
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ]);
    }
}
