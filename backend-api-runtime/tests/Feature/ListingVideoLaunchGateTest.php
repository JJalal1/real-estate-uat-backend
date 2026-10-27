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
        // Authentication remains mandatory even while the feature is closed.
        $this->getJson('/api/properties/1/video')->assertUnauthorized();
        $this->postJson('/api/properties/1/video', ['upload_id' => 'not-a-uuid'])->assertUnauthorized();
        $controller=app(\App\Http\Controllers\Api\ListingVideoController::class);
        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);
        $controller->show(\Illuminate\Http\Request::create('/api/properties/1/video'),new \App\Models\Property());
    }

    public function test_video_processing_is_off_by_default(): void
    {
        $this->assertFalse((bool) config('listing_video.uploads_enabled', false));
        $this->assertFalse((bool) config('listing_video.processing_enabled', false));
        $this->assertTrue((bool) config('listing_video.worker_heartbeat_required', false));
    }
}
