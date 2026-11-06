<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class UatListingAiProbeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->app['env'] = 'staging';
        config(['gemini.enabled'=>true, 'gemini.key'=>'fixture-server-key',
            'gemini.model'=>'gemini-3.1-flash-lite', 'gemini.daily_limit'=>200]);
        Http::preventStrayRequests();
    }

    private function model(array $value): void
    {
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::response([
            'candidates'=>[['content'=>['parts'=>[['text'=>json_encode($value)]]]]],
        ])]);
    }

    private function receipt(): array
    {
        $output = trim(Artisan::output());
        $this->assertStringStartsWith('AQER_LISTING_AI_PROBE ', $output);
        $this->assertStringNotContainsString('fixture-server-key', $output);
        $this->assertStringNotContainsString('private-provider-content', $output);
        return json_decode(substr($output, strlen('AQER_LISTING_AI_PROBE ')), true, 16, JSON_THROW_ON_ERROR);
    }

    public function test_production_is_refused_before_any_provider_request(): void
    {
        $this->app['env'] = 'production';
        $this->assertSame(1, Artisan::call('uat:listing-ai-check'));
        $this->assertSame('environment_refused', $this->receipt()['status']);
        Http::assertNothingSent();
    }

    public function test_real_extractor_contract_matches_and_does_not_write_listings(): void
    {
        $this->model(['fields'=>['type'=>'apartment','purpose'=>'rent','governorate'=>'صنعاء',
            'floor_number'=>'2','bedrooms'=>3,'bathrooms'=>2,'has_parking'=>false,'building_facade'=>'north']]);
        $this->assertSame(0, Artisan::call('uat:listing-ai-check'));
        $r = $this->receipt();
        $this->assertSame('passed', $r['status']);
        $this->assertTrue($r['required_facts_match']);
        $this->assertFalse($r['native_acceptance']);
        Http::assertSentCount(1);
        $this->assertDatabaseCount('properties', 0);
        $this->assertDatabaseCount('listing_editor_drafts', 0);
    }

    public function test_validation_diagnostic_exports_only_known_field_names(): void
    {
        $this->model(['fields'=>['type'=>'apartment','bedrooms'=>0,'title'=>str_repeat('private-provider-content',10)]]);
        $this->assertSame(1, Artisan::call('uat:listing-ai-check'));
        $r = $this->receipt();
        $this->assertSame('none', $r['provider_stage']);
        $this->assertSame(['bedrooms','title'], $r['invalid_field_names']);
        $this->assertSame('unavailable', $r['status']);
    }

    public function test_provider_http_failure_is_distinct_from_validation(): void
    {
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::response(['error'=>'private-provider-content'],400)]);
        $this->assertSame(1, Artisan::call('uat:listing-ai-check'));
        $r = $this->receipt();
        $this->assertSame('provider_http_400', $r['provider_stage']);
        $this->assertSame([], $r['invalid_field_names']);
        Http::assertSentCount(1);
    }

    public function test_unknown_provider_keys_are_not_exported_as_diagnostics(): void
    {
        $this->model(['fields'=>['private-provider-content'=>'private-provider-content']]);
        $this->assertSame(1, Artisan::call('uat:listing-ai-check'));
        $this->assertSame(['other_schema'], $this->receipt()['invalid_field_names']);
    }

    public function test_sparse_valid_model_response_uses_existing_facts_and_explicit_labels(): void
    {
        $this->model(['fields'=>['type'=>'apartment','purpose'=>'rent']]);
        $this->assertSame(0, Artisan::call('uat:listing-ai-check'));
        $r = $this->receipt();
        $this->assertSame('ai', $r['proposal_source']);
        $this->assertSame([], $r['mismatched_required_fields']);
        $this->assertSame([], $r['missing_required_proposals']);
        Http::assertSentCount(1);
    }

    public function test_literal_fallback_is_not_accepted_even_when_required_facts_are_complete(): void
    {
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::response([],400)]);
        $this->assertSame(1, Artisan::call('uat:listing-ai-check'));
        $r = $this->receipt();
        $this->assertSame('text', $r['proposal_source']);
        $this->assertSame('unavailable', $r['status']);
        $this->assertSame([], $r['mismatched_required_fields']);
        $this->assertFalse($r['required_facts_match']);
        Http::assertSentCount(1);
    }
}
