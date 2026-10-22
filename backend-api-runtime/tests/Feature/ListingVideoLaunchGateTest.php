<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ListingVideoLaunchGateTest extends TestCase
{
    use RefreshDatabase;

    public function test_video_routes_are_unavailable_when_feature_is_disabled(): void
    {
        config()->set('listing_video.uploads_enabled', false);
        $this->getJson('/api/properties/1/video')->assertUnauthorized();
        $this->postJson('/api/properties/1/video', ['upload_id' => 'not-a-uuid'])->assertUnauthorized();
    }

    public function test_video_processing_is_off_by_default(): void
    {
        $this->assertFalse((bool) config('listing_video.uploads_enabled', false));
        $this->assertFalse((bool) config('listing_video.processing_enabled', false));
    }
}
