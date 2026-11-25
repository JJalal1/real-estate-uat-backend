<?php

namespace Tests\Feature;

use App\Jobs\MatchPublishedProperty;
use App\Jobs\PrepareListingImage;
use App\Jobs\RunScheduledBackgroundTask;
use App\Services\BackgroundQueue;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class BackgroundPreparationTest extends TestCase
{
    use RefreshDatabase;

    public function test_inactive_missing_expired_and_full_workers_cannot_accept_work(): void
    {
        $queues = app(BackgroundQueue::class);
        $job = new MatchPublishedProperty(10);
        $queues->heartbeat('discovery');
        $this->assertFalse($queues->submit('instant_search', $job));
        config(['background.features.instant_search'=>true, 'background.capacity'=>1]);
        $this->travel(46)->seconds();
        $this->assertFalse($queues->submit('instant_search', $job));
        $queues->heartbeat('media');
        $this->assertFalse($queues->submit('instant_search', $job));
        $queues->heartbeat('discovery');
        $this->assertTrue($queues->submit('instant_search', $job));
        $this->assertFalse($queues->submit('instant_search', new MatchPublishedProperty(11)));
        $this->assertDatabaseCount('jobs', 1);
    }

    public function test_schedule_retry_rollback_and_queue_isolation(): void
    {
        $queues = app(BackgroundQueue::class);
        config(['background.features.images'=>true, 'background.features.reports'=>true]);
        $queues->heartbeat('reports');
        $this->assertFalse($queues->submit('images', new PrepareListingImage(1, 'fixture')));
        DB::beginTransaction();
        $this->artisan('background:tick')->assertSuccessful();
        $this->assertDatabaseCount('jobs', 1);
        DB::rollBack();
        $this->assertDatabaseCount('jobs', 0);
        $this->assertDatabaseCount('background_receipts', 0);
        $this->artisan('background:tick')->assertSuccessful();
        $this->artisan('background:tick')->assertSuccessful();
        $this->assertDatabaseCount('jobs', 1);
        $this->assertDatabaseHas('jobs', ['queue'=>'reports']);
    }

    public function test_worker_rechecks_a_disabled_scheduled_task(): void
    {
        (new RunScheduledBackgroundTask('reports', now()->timestamp))->handle(app(BackgroundQueue::class));
        $this->assertFalse(\Illuminate\Support\Facades\Cache::has('general-manager:insights:v2'));
    }
}
