<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class RenderHealthProbePerformanceTest extends TestCase
{
    public function test_render_liveness_probe_does_not_touch_the_remote_database(): void
    {
        DB::shouldReceive('select')->never();

        $this->withHeader('User-Agent', 'Render/1.0')
            ->getJson('/api/health')
            ->assertOk()
            ->assertExactJson([
                'status' => 'ok',
                'liveness' => true,
            ]);
    }

    public function test_normal_health_check_keeps_the_deep_database_contract(): void
    {
        $this->withHeader('User-Agent', 'UAT-CI/1.0')
            ->getJson('/api/health')
            ->assertOk()
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('database', true);
    }
}
