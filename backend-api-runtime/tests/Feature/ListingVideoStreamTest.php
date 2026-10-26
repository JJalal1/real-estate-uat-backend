<?php

namespace Tests\Feature;

use App\Models\ListingVideo;
use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ListingVideoStreamTest extends TestCase
{
    use RefreshDatabase;

    private function property(string $status): Property
    {
        $owner = User::query()->create([
            'name' => 'Stream owner',
            'email' => 'video-stream-owner@example.test',
            'password' => 'StreamTestPass123!',
            'account_status' => User::STATUS_ACTIVE,
        ]);
        return Property::query()->create([
            'user_id' => $owner->id,
            'title' => 'Stream fixture',
            'purpose' => 'sale',
            'type' => 'shop',
            'price' => 100,
            'currency' => 'YER',
            'latitude' => 15.3,
            'longitude' => 44.1,
            'status' => $status,
            'review_status' => $status === 'published' ? 'approved' : 'draft',
        ]);
    }

    private function video(Property $property): ListingVideo
    {
        $path = 'listing-video-display/fixture/playback.mp4';
        Storage::disk('local')->put($path, '0123456789ABCDEFGHIJ');
        Storage::disk('local')->put('listing-video-display/fixture/poster.jpg', 'jpeg');
        return ListingVideo::query()->create([
            'property_id' => $property->id,
            'upload_id' => 'bcf7c61e-e795-46f9-947e-876a67e6dfc8',
            'status' => 'ready',
            'moderation_status' => 'approved',
            'original_path' => 'listing-videos/fixture/original.mp4',
            'playback_path' => $path,
            'playback_size_bytes' => 20,
            'poster_path' => 'listing-video-display/fixture/poster.jpg',
            'mime_type' => 'video/mp4',
            'size_bytes' => 20,
            'content_sha256' => str_repeat('a', 64),
        ]);
    }

    public function test_published_processed_video_supports_small_byte_ranges_without_exposing_original(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        $video = $this->video($this->property('published'));

        $this->withHeaders(['Range' => 'bytes=5-9'])
            ->get('/api/property-videos/'.$video->id.'/stream')
            ->assertStatus(206)
            ->assertHeader('Content-Range', 'bytes 5-9/20')
            ->assertSee('56789', false);
        $privateRange = $this->withHeaders(['Range' => 'bytes=0-4'])
            ->get('/api/property-videos/'.$video->id.'/stream')
            ->assertStatus(206);
        // Symfony normalizes Cache-Control directive order. Assert the
        // two required protections semantically rather than their order.
        $directives = array_map('trim', explode(',',
            (string) $privateRange->headers->get('Cache-Control')));
        $this->assertContains('private', $directives);
        $this->assertContains('no-store', $directives);
        $this->get('/api/property-videos/'.$video->id.'/poster')->assertOk();
        $this->withHeaders(['Range' => 'bytes=20-99'])
            ->get('/api/property-videos/'.$video->id.'/stream')
            ->assertStatus(416);
        $this->get('/api/property-videos/'.$video->id.'/source')->assertNotFound();
    }

    public function test_draft_video_derivatives_are_not_publicly_accessible(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        $video = $this->video($this->property('draft'));
        $this->get('/api/property-videos/'.$video->id.'/poster')->assertNotFound();
        $this->get('/api/property-videos/'.$video->id.'/stream')->assertNotFound();
    }
    public function test_unreviewed_video_cannot_be_streamed_from_published_listing(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        $property = $this->property('published');
        $video = $this->video($property);
        $video->forceFill([
            'moderation_status' => 'pending',
            'moderated_at' => null,
            'moderated_by_user_id' => null,
        ])->save();

        $this->get('/api/property-videos/'.$video->id.'/stream')->assertNotFound();
        $this->get('/api/property-videos/'.$video->id.'/poster')->assertNotFound();
        $detail = $this->getJson('/api/properties/'.$property->id)->assertOk();
        $this->assertNull($detail->json('data.video'));
    }

}

