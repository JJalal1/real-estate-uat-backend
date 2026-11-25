<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyFavorite;
use App\Models\User;
use App\Services\PropertyPriceChangeAlertService;
use App\Services\SavedSearchAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ProductExperienceSavedSearchTest extends TestCase
{
    use RefreshDatabase;

    public function test_saved_search_is_account_bound_deduplicated_and_matches_filters(): void
    {
        [$user, $headers] = $this->user('searcher@example.test', '+967770001001');
        [, $otherHeaders] = $this->user('other@example.test', '+967770001002');
        $this->property('matching villa', 'sale', 'villa', 50000000, 'published');
        $this->property('too expensive villa', 'sale', 'villa', 90000000, 'published');

        $payload = [
            'name' => 'فلل مناسبة',
            'alert_frequency' => 'instant',
            'filters' => [
                'purpose' => 'sale',
                'type' => 'villa',
                'max_price' => 60000000,
            ],
        ];

        $created = $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)
            ->assertCreated()
            ->assertJsonPath('data.name', 'فلل مناسبة')
            ->assertJsonPath('data.matching_count', 1);
        $id = (int) $created->json('data.id');

        $this->withHeaders($headers)->postJson('/api/saved-searches', $payload)
            ->assertOk()
            ->assertJsonPath('data.id', $id);

        $this->withHeaders($otherHeaders)->patchJson('/api/saved-searches/'.$id, [
            'name' => 'لا يجب أن يتغير',
        ])->assertNotFound();

        $this->withHeaders($headers)->patchJson('/api/saved-searches/'.$id, [
            'alert_frequency' => 'daily',
        ])->assertOk()->assertJsonPath('data.alert_frequency', 'daily');

        $this->assertDatabaseHas('saved_property_searches', [
            'id' => $id,
            'user_id' => $user->id,
            'alert_frequency' => 'daily',
        ]);
    }

    public function test_instant_saved_search_alert_does_not_notify_listing_owner(): void
    {
        [$searcher, $headers] = $this->user('alert@example.test', '+967770001003');
        [$owner] = $this->user('owner@example.test', '+967770001004');

        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'شقق إيجار',
            'alert_frequency' => 'instant',
            'filters' => ['purpose' => 'rent', 'type' => 'apartment'],
        ])->assertCreated();

        $listing = $this->property('شقة جديدة', 'rent', 'apartment', 150000, 'published', $owner);
        $count = app(SavedSearchAlertService::class)->notifyPublishedProperty($listing->id);

        $this->assertSame(1, $count);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $searcher->id,
            'type' => 'saved_search_match',
            'entity_type' => 'property',
            'entity_id' => $listing->id,
        ]);
        $this->assertDatabaseMissing('user_notifications', [
            'user_id' => $owner->id,
            'type' => 'saved_search_match',
            'entity_id' => $listing->id,
        ]);
    }

    public function test_published_favorite_price_change_notifies_savers_but_not_owner(): void
    {
        [$saver] = $this->user('price-saver@example.test', '+967770001005');
        [$owner] = $this->user('price-owner@example.test', '+967770001006');
        $listing = $this->property('فيلا محفوظة', 'sale', 'villa', 60000000, 'published', $owner);

        PropertyFavorite::query()->create([
            'user_id' => $saver->id,
            'property_id' => $listing->id,
        ]);
        PropertyFavorite::query()->create([
            'user_id' => $owner->id,
            'property_id' => $listing->id,
        ]);

        $count = app(PropertyPriceChangeAlertService::class)->notify(
            $listing->id,
            60000000,
            55000000,
        );

        $this->assertSame(1, $count);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $saver->id,
            'type' => 'favorite_price_changed',
            'entity_type' => 'property',
            'entity_id' => $listing->id,
        ]);
        $this->assertDatabaseMissing('user_notifications', [
            'user_id' => $owner->id,
            'type' => 'favorite_price_changed',
            'entity_id' => $listing->id,
        ]);
    }

    public function test_price_change_alert_ignores_unpublished_listing(): void
    {
        [$saver] = $this->user('draft-saver@example.test', '+967770001007');
        [$owner] = $this->user('draft-owner@example.test', '+967770001008');
        $listing = $this->property('مسودة محفوظة', 'rent', 'apartment', 180000, 'draft', $owner);

        PropertyFavorite::query()->create([
            'user_id' => $saver->id,
            'property_id' => $listing->id,
        ]);

        $count = app(PropertyPriceChangeAlertService::class)->notify(
            $listing->id,
            180000,
            170000,
        );

        $this->assertSame(0, $count);
        $this->assertDatabaseMissing('user_notifications', [
            'user_id' => $saver->id,
            'type' => 'favorite_price_changed',
            'entity_id' => $listing->id,
        ]);
    }

    public function test_background_price_retries_and_late_publication_daily_digest(): void
    {
        [$saver, $headers] = $this->user('queue-search@example.test', '+967770002021');
        [$owner] = $this->user('queue-owner@example.test', '+967770002022');
        $listing = $this->property('fixture flat', 'rent', 'apartment', 200000, 'published', $owner);
        PropertyFavorite::create(['user_id'=>$saver->id,'property_id'=>$listing->id]);
        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name'=>'daily', 'alert_frequency'=>'daily', 'filters'=>['purpose'=>'rent'],
        ])->assertCreated();
        $this->travel(2)->hours();
        $listing->forceFill(['published_at'=>now()])->saveQuietly();
        $job = new \App\Jobs\NotifyFavoritePrice($listing->id, 200000, 190000, 'one-change', 'YER', now()->timestamp);
        $job->handle(app(PropertyPriceChangeAlertService::class));
        $job->handle(app(PropertyPriceChangeAlertService::class));
        $this->assertSame(1, \App\Models\UserNotification::where('type','favorite_price_changed')->count());
        $this->travelTo(now('Asia/Aden')->addDay()->startOfDay()->addMinute());
        $daily = app(SavedSearchAlertService::class);
        $this->assertSame(1, $daily->sendDailyDigests());
        $this->assertSame(0, $daily->sendDailyDigests());
    }

    public function test_image_preparation_uses_original_and_ignores_removed_image(): void
    {
        \Illuminate\Support\Facades\Storage::fake('local');
        $listing = $this->property('photo test', 'sale', 'villa', 50000, 'published');
        $images = app(\App\Services\ListingImageService::class);
        $file = \Illuminate\Http\UploadedFile::fake()->image('listing.jpg', 480, 320);
        $path = $images->store($file, 'listing-originals/'.$listing->id, cardFirst: true);
        $image = $listing->images()->create(['path'=>$path, 'sort_order'=>0, 'is_primary'=>true]);
        $disk = \Illuminate\Support\Facades\Storage::disk('local');
        $disk->assertExists($images->variantPath($path, 'card'));
        $disk->assertMissing($images->variantPath($path, 'thumb'));
        $job = new \App\Jobs\PrepareListingImage($image->id, hash('sha256', $path));
        $job->handle($images);
        $target = $images->variantPath($path, 'thumb');
        $this->assertSame('image/jpeg', getimagesizefromstring($disk->get($target))['mime']);
        $job->handle($images);
        $image->delete();
        $disk->delete($target);
        $job->handle($images);
        $disk->assertMissing($target);
    }

    public function test_listing_deadline_is_opt_in_deduplicated_and_does_not_unpublish(): void
    {
        $listing = $this->property('expiry test', 'rent', 'apartment', 123456, 'published');
        $service = app(\App\Services\DeadlineReminderService::class);
        $service->listings();
        $this->assertDatabaseMissing('user_notifications', ['type'=>'listing_expiry_reminder']);
        config(['background.rent_days'=>1, 'background.expiry_lead_minutes'=>1500]);
        $service->listings();
        $service->listings();
        $notice = \App\Models\UserNotification::where('type','listing_expiry_reminder')->sole();
        $this->assertTrue($service->stillDue($notice));
        $this->assertSame('published', $listing->fresh()->status);
        $listing->forceFill(['published_at'=>now()->addMinute()])->saveQuietly();
        $this->assertFalse($service->stillDue($notice));
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Experience User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $plain = 'experience_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'experience-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }

    private function property(
        string $title,
        string $purpose,
        string $type,
        float $price,
        string $status,
        ?User $owner = null,
    ): Property {
        $owner ??= User::query()->create([
            'name' => 'Listing Owner '.$title,
            'email' => substr(hash('sha256', $title), 0, 20).'@example.test',
            'phone' => '+967'.substr(preg_replace('/\D/', '', (string) crc32($title)), 0, 9),
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);

        return Property::query()->create([
            'user_id' => $owner->id,
            'title' => $title,
            'purpose' => $purpose,
            'type' => $type,
            'price' => $price,
            'currency' => 'YER',
            'area_m2' => 180,
            'address' => 'صنعاء',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => $status,
            'review_status' => $status === 'published' ? 'approved' : 'draft',
            'published_at' => $status === 'published' ? now() : null,
        ]);
    }
}
