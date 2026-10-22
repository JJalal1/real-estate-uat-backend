<?php

namespace Tests\Feature;

use App\Jobs\ProcessListingVideo;
use App\Models\ListingVideo;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\ListingVideoTranscoder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/** Disposable, synthetic full cycle: MP4 input -> private original -> worker -> ranges. */
class ListingVideoFullCycleTest extends TestCase
{
    use RefreshDatabase;

    public function test_video_upload_process_publish_and_stream_from_private_storage(): void
    {
        config()->set('services.supabase_storage.enabled', false);
        config()->set('listing_video.uploads_enabled', true);
        config()->set('listing_video.processing_enabled', true);
        Storage::fake('local');
        Storage::fake('public');
        Queue::fake();

        $owner = User::query()->create([
            'name' => 'Video full cycle tester', 'email' => 'video-cycle@example.test',
            'phone' => '+967777560128', 'password' => Hash::make('VideoCyclePass123!'),
            'account_status' => User::STATUS_ACTIVE, 'phone_verified_at' => now(),
            'profile_completed_at' => now(), 'identity_policy_version' => 2,
        ]);
        $owner->roles()->sync([
            Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()],
        ]);
        $token = 'video-cycle-synthetic-only';
        $owner->apiTokens()->create([
            'name' => 'test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour(),
        ]);

        $listing = Property::query()->create([
            'user_id' => $owner->id, 'title' => 'Synthetic media cycle',
            'type' => 'shop', 'purpose' => 'sale', 'price' => 100000,
            'currency' => 'YER', 'address' => 'Sanaa', 'latitude' => 15.3,
            'longitude' => 44.2, 'status' => 'draft', 'review_status' => 'draft',
        ]);

        $temp = tempnam(sys_get_temp_dir(), 'aqer-video-e2e-');
        $this->assertNotFalse($temp);
        try {
            $source = $temp.'.mp4';
            $make = new Process([
                'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
                '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=10',
                '-t', '2', '-c:v', 'libx264', '-threads', '1',
                '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-y', $source,
            ]);
            $make->setTimeout(40);
            $make->mustRun();
            $file = new UploadedFile($source, 'synthetic.mp4', 'video/mp4', null, true);
            $this->withHeaders(['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json'])
                ->post('/api/properties/'.$listing->id.'/video', [
                    'upload_id' => (string) Str::uuid(), 'video' => $file,
                ])->assertStatus(202)->assertJsonPath('data.status', 'uploaded');

            $record = ListingVideo::query()->firstOrFail();
            $this->assertNotEmpty($record->original_path);
            Storage::disk('local')->assertExists($record->original_path);
            $this->assertSame([], Storage::disk('public')->allFiles());
            (new ProcessListingVideo($record->id))->handle(
                app(CloudAssetStorageService::class),
                app(ListingVideoTranscoder::class),
            );

            $ready = $record->fresh();
            $this->assertSame('ready', $ready->status);
            $this->assertGreaterThan(0, $ready->playback_size_bytes);
            Storage::disk('local')->assertExists($ready->playback_path);
            Storage::disk('local')->assertExists($ready->poster_path);

            // Re-delivering a queue job must not reprocess ready media.
            (new ProcessListingVideo($record->id))->handle(
                app(CloudAssetStorageService::class),
                app(ListingVideoTranscoder::class),
            );
            $this->assertSame(1, $ready->fresh()->attempts);
            $this->assertSame($ready->playback_path, $ready->fresh()->playback_path);

            // Simulate the explicit staff confirmation for a published
            // listing fixture; the workflow requires video_review_confirmed.
            $ready->forceFill([
                'moderation_status' => 'approved',
                'moderated_at' => now(),
                'moderated_by_user_id' => $owner->id,
            ])->save();
            $listing->forceFill([
                'status' => 'published', 'review_status' => 'approved',
                'availability_status' => 'available', 'published_at' => now(),
            ])->save();
            $this->getJson('/api/properties/'.$listing->id)
                ->assertOk()
                ->assertJsonPath('data.video.id', $record->id);
            $this->withHeaders(['Range' => 'bytes=0-1023'])
                ->get('/api/property-videos/'.$record->id.'/stream')
                ->assertStatus(206)
                ->assertHeader('Content-Range', 'bytes 0-1023/'.$ready->playback_size_bytes);
        } finally {
            @unlink($temp);
            @unlink($temp.'.mp4');
        }
    }

    public function test_processing_off_means_no_private_original_is_accepted(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('listing_video.processing_enabled', false);
        $this->postJson('/api/properties/1/video', [
            'upload_id' => (string) Str::uuid(),
        ])->assertNotFound();
    }
}
