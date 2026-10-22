<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Models\ListingVideo;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

class ListingVideoApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config()->set('listing_video.processing_enabled', true);
        Queue::fake();
    }

    private function actor(string $name): array
    {
        $user = User::query()->create([
            'name' => 'Test advertiser',
            'email' => $name.'@video.example.test',
            'phone' => '+9677331'.str_pad((string) (abs(crc32($name)) % 10000), 4, '0', STR_PAD_LEFT),
            'password' => Hash::make('VideoPass123!'),
            'account_status' => User::STATUS_ACTIVE,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'identity_policy_version' => 2,
        ]);
        $user->roles()->sync([
            Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()],
        ]);
        $token = 'test-video-'.$name;
        $user->apiTokens()->create([
            'name' => 'test',
            'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function property(User $user): Property
    {
        return Property::query()->create([
            'user_id' => $user->id,
            'title' => 'Video listing',
            'type' => 'shop',
            'purpose' => 'rent',
            'price' => 70000,
            'currency' => 'YER',
            'address' => 'Sanaa',
            'latitude' => 15.2,
            'longitude' => 44.1,
            'status' => 'draft',
            'review_status' => 'draft',
        ]);
    }

    private function video(): UploadedFile
    {
        $header = pack('N', 24).'ftypisom'.pack('N', 0).'isom';
        return UploadedFile::fake()->createWithContent('clip.mp4', $header.str_repeat("\0", 8));
    }

    public function test_owned_draft_video_upload_is_idempotent_and_original_is_private(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        // Uploads must fail closed when the asynchronous worker is not enabled.
        // Queue::fake() in setUp() isolates this API regression from the worker.
        config()->set('listing_video.processing_enabled', true);
        Storage::fake('local');
        Storage::fake('public');
        [$user, $headers] = $this->actor('owner');
        $property = $this->property($user);
        $key = (string) Str::uuid();
        $url = '/api/properties/'.$property->id.'/video';

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(202)->assertJsonPath('data.status', 'uploaded');
        $this->assertDatabaseCount('listing_videos', 1);
        $record = ListingVideo::query()->firstOrFail();
        Storage::disk('local')->assertExists($record->original_path);
        $this->assertSame([], Storage::disk('public')->allFiles());

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(202)->assertJsonPath('data.id', $record->id);
        $this->assertDatabaseCount('listing_videos', 1);

        $this->withHeaders($headers)->getJson($url)->assertOk()->assertJsonPath('data.status', 'uploaded');
        $this->withHeaders($headers)->deleteJson($url)->assertOk();
        $this->assertDatabaseCount('listing_videos', 0);
        Storage::disk('local')->assertMissing($record->original_path);
    }

    public function test_foreign_user_cannot_read_or_replace_unpublished_video(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        Storage::fake('local');
        [$owner, $ownerHeaders] = $this->actor('video-owner');
        [, $attackerHeaders] = $this->actor('video-attacker');
        $property = $this->property($owner);
        $url = '/api/properties/'.$property->id.'/video';

        $this->withHeaders($ownerHeaders)->post($url, [
            'upload_id' => (string) Str::uuid(),
            'video' => $this->video(),
        ])->assertStatus(202);

        $this->withHeaders($attackerHeaders)->getJson($url)->assertNotFound();
        $this->withHeaders($attackerHeaders)->post($url, [
            'upload_id' => (string) Str::uuid(), 'video' => $this->video(),
        ])->assertNotFound();
        $this->withHeaders($attackerHeaders)->deleteJson($url)->assertNotFound();
        $this->assertDatabaseCount('listing_videos', 1);
    }

    public function test_published_listing_does_not_accept_new_video_even_from_owner(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        [$owner, $headers] = $this->actor('published-owner');
        $property = $this->property($owner);
        $property->forceFill(['status' => 'published', 'review_status' => 'approved'])->save();
        $this->withHeaders($headers)->post('/api/properties/'.$property->id.'/video', [
            'upload_id' => (string) Str::uuid(),
            'video' => $this->video(),
        ])->assertStatus(409);
    }
}
