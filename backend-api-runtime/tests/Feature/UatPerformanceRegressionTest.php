<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertySaiTerm;
use App\Models\User;
use App\Services\RequestPerformance;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UatPerformanceRegressionTest extends TestCase
{
    use RefreshDatabase;

    /** Also run unchanged against the pinned pre-fix controller in CI. */
    public function test_marketplace_measurement_preserves_prices_terms_privacy_and_section_order(): void
    {
        $this->travelTo(now()->startOfDay());
        $owner = User::create(['name'=>'Synthetic performance owner','email'=>'performance-owner@example.test','password'=>'unusable']);
        $indices = [];
        for ($i = 0; $i < 12; $i++) {
            $property = Property::create(['user_id'=>$owner->id,'title'=>'Synthetic performance '.$i,
                'type'=>'shop','purpose'=>'sale','price'=>100000 + $i,'currency'=>'YER','latitude'=>13.96,'longitude'=>44.18,
                'address'=>'إب','status'=>'published','review_status'=>'approved','published_at'=>now(),
                'spotlight_until'=>now()->addDay(),'price_display_mode'=>'includes_sai']);
            $indices[$property->id] = $i;
            $term = PropertySaiTerm::create(['property_id'=>$property->id,'version'=>1,'advertiser_type'=>'owner',
                'purpose'=>'sale','source_mode'=>'owner_fixed','sai_rate_percent'=>1,'payer'=>'buyer',
                'calculation_basis'=>'final_sale_value','platform_share_percent'=>100,'broker_share_percent'=>0,
                'platform_terms_status'=>'not_required','created_by_user_id'=>$owner->id]);
            $property->forceFill(['current_sai_term_id'=>$term->id, 'spotlight_until'=>now()->addDay()])->saveQuietly();
            if ($i % 2 === 0) DB::table('property_sai_attestations')->insert(['property_id'=>$property->id,
                'sai_term_id'=>$term->id,'user_id'=>$owner->id,'terms_version'=>1,'text_snapshot'=>'Synthetic explicit attestation',
                'accepted_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        }
        DB::connection()->enableQueryLog();
        DB::connection()->flushQueryLog();
        try {
            $response = $this->getJson('/api/marketplace?governorate=إب')->assertOk();
            $queries = DB::getQueryLog();
        } finally {
            DB::connection()->disableQueryLog();
        }
        $sections = $response->json('data.sections');
        $this->assertSame(['spotlight','latest','sale'], $response->json('data.section_order'));
        $this->assertCount(6, $sections['latest']);
        $this->assertSame([], $sections['rent']);
        $snapshot = [];
        foreach (['spotlight','latest','sale'] as $section) {
            $this->assertSame(array_column($sections['latest'], 'id'), array_column($sections[$section], 'id'));
            foreach ($sections[$section] as $row) {
                $base = 100000 + $indices[$row['id']];
                $this->assertEquals($base, $row['base_price']);
                $this->assertEquals(round($base * .01, 2), $row['sai']['amount']);
                $this->assertEquals(round($base * 1.01, 2), $row['display_price']);
                $this->assertFalse($row['financial_hold']);
                $this->assertSame($indices[$row['id']] % 2 !== 0, $row['sai_attestation_required']);
                $this->assertNull($row['sai_attestation_text']);
                $this->assertArrayNotHasKey('platform_share_percent', $row['sai']);
                $snapshot[$section][] = [$indices[$row['id']],$row['base_price'],$row['display_price'],$row['sai'],$row['sai_attestation_required']];
            }
        }
        $selects = array_filter($queries, fn ($query) => str_starts_with(strtolower($query['query']), 'select'));
        $terms = count(array_filter($selects, fn ($query) => str_contains($query['query'], 'from "property_sai_terms"')));
        $attestations = count(array_filter($selects, fn ($query) => str_contains($query['query'], 'from "property_sai_attestations"')));
        fwrite(STDOUT, '\nAQER_MARKETPLACE_QUERY_MEASUREMENT '.json_encode(['baseline'=>getenv('AQER_PERF_BASELINE') === '1',
            'driver'=>DB::getDriverName(),'queries'=>count($queries),'term_selects'=>$terms,'attestation_selects'=>$attestations,
            'semantic_sha256'=>hash('sha256',json_encode($snapshot))])."\n");
        if (getenv('AQER_PERF_BASELINE') !== '1') {
            $this->assertSame(1, $terms);
            $this->assertSame(1, $attestations);
            $this->assertLessThanOrEqual(25, count($queries));
        }
    }

    public function test_diagnostic_query_counters_are_per_request_and_not_cumulative(): void
    {
        $first = $this->withHeader('X-Aqer-Diagnostics','perf-109')->getJson('/api/health')->assertOk();
        $second = $this->getJson('/api/health')->assertOk();
        $this->assertSame($first->headers->get('X-Aqer-DB-Queries'), $second->headers->get('X-Aqer-DB-Queries'));
        $this->assertSame(DB::getDriverName() === 'pgsql' ? '2' : '1', $second->headers->get('X-Aqer-DB-Queries'));
        $second->assertHeader('X-Aqer-Storage-Requests','0')->assertHeader('Cache-Control','no-store, private');
        $this->assertMatchesRegularExpression('/app;dur=[\d.]+, db;dur=[\d.]+, storage;dur=[\d.]+, php;dur=[\d.]+/', $second->headers->get('Server-Timing'));
        $this->flushHeaders();
        $this->getJson('/api/health')->assertHeaderMissing('Server-Timing')->assertHeaderMissing('X-Aqer-DB-Queries');
    }

    public function test_twenty_distinct_advertisers_do_not_add_per_owner_financial_queries(): void
    {
        \Illuminate\Support\Facades\Cache::put('broker-availability-swept',true,60);
        $expected=[];
        for($i=0;$i<20;$i++) {
            $owner=User::create(['name'=>'Synthetic distinct owner '.$i,'email'=>'distinct-'.$i.'@example.test','password'=>'unusable']);
            $property=Property::create(['user_id'=>$owner->id,'title'=>'Distinct owner listing '.$i,
                'type'=>'shop','purpose'=>'sale','price'=>100000+$i,'currency'=>'YER','latitude'=>13.96,'longitude'=>44.18,
                'address'=>'إب','status'=>'published','review_status'=>'approved','published_at'=>now()]);
            $expected[$property->id]=(float)$property->price;
        }
        DB::connection()->enableQueryLog();DB::connection()->flushQueryLog();
        try {
            $response=$this->getJson('/api/properties?per_page=20')->assertOk();
            $queries=DB::getQueryLog();
        } finally { DB::connection()->disableQueryLog(); }
        $this->assertCount(20,$response->json('data'));
        foreach($response->json('data') as $row) {
            $this->assertEquals($expected[$row['id']],$row['base_price']);
            $this->assertEquals($expected[$row['id']],$row['display_price']);
            $this->assertFalse($row['financial_hold']);
        }
        $reads=array_filter($queries,fn ($q)=>str_contains($q['query'],'from "property_platform_receivables"'));
        $this->assertLessThanOrEqual(4,count($reads));
        $this->assertLessThanOrEqual(25,count($queries));
        fwrite(STDOUT,"\nAQER_DISTINCT_OWNER_QUERIES ".json_encode(['owners'=>20,'queries'=>count($queries),'receivable_reads'=>count($reads)])."\n");
    }

    public function test_nearby_measurement_preserves_compact_primary_photo_summaries(): void
    {
        \Illuminate\Support\Facades\Cache::store('file')->flush();
        \Illuminate\Support\Facades\Cache::put('broker-availability-swept',true,60);
        $owner = User::create(['name'=>'Synthetic nearby owner','email'=>'nearby-performance@example.test','password'=>'unusable']);
        for ($i=0; $i<20; $i++) {
            $property = Property::create(['user_id'=>$owner->id,'title'=>'Nearby '.$i,'type'=>'shop','purpose'=>'sale',
                'price'=>10000,'currency'=>'YER','latitude'=>15.123456 + $i*.000001,'longitude'=>44.654321,
                'status'=>'published','review_status'=>'approved','published_at'=>now()]);
            foreach ([0,1] as $n) $property->images()->create(['path'=>'listing-originals/synthetic-'.$i.'-'.$n.'.jpg','sort_order'=>$n,'is_primary'=>$n===0]);
        }
        DB::connection()->enableQueryLog(); DB::connection()->flushQueryLog();
        try {
            $response = $this->getJson('/api/properties/nearby?latitude=15.123456&longitude=44.654321&radius_km=1')->assertOk();
            $queries = DB::getQueryLog();
        } finally { DB::connection()->disableQueryLog(); }
        $this->assertCount(20,$response->json('data'));
        foreach ($response->json('data') as $row) {
            $this->assertArrayNotHasKey('image_count',$row);
            $this->assertCount(1,$row['image_urls']);
            $this->assertSame($row['main_image'],$row['image_urls'][0]);
        }
        $photoReads = count(array_filter($queries,fn ($q)=>str_contains($q['query'],'from "property_images"')));
        fwrite(STDOUT,"\nAQER_NEARBY_QUERY_MEASUREMENT ".json_encode(['baseline'=>getenv('AQER_PERF_BASELINE') === '1',
            'driver'=>DB::getDriverName(),'rows'=>20,'images'=>40,'photo_selects'=>$photoReads,'queries'=>count($queries)])."\n");
        if (getenv('AQER_PERF_BASELINE') !== '1') $this->assertSame(1,$photoReads);
    }

    public function test_published_media_does_not_open_a_token_or_permission_lookup_but_private_media_still_authenticates(): void
    {
        \Illuminate\Support\Facades\Storage::fake('local');
        $owner = User::create(['name'=>'Synthetic media owner','email'=>'media-perf@example.test','password'=>'unusable','account_status'=>'active']);
        $property = Property::create(['user_id'=>$owner->id,'title'=>'Synthetic media','type'=>'shop','purpose'=>'sale',
            'price'=>10000,'currency'=>'YER','latitude'=>15.12,'longitude'=>44.65,'status'=>'published','review_status'=>'approved']);
        $service = app(\App\Services\ListingImageService::class);
        $path = $service->store(\Illuminate\Http\UploadedFile::fake()->image('synthetic.jpg',80,40),'listing-originals/synthetic');
        $image = $property->images()->create(['path'=>$path,'is_primary'=>true,'sort_order'=>0]);
        $bearer = app(\App\Services\ApiTokenService::class)->issue($owner,request())['plain_text_token'];
        $this->withToken($bearer)->withHeader('X-Aqer-Diagnostics','perf-109')->get('/api/property-media/'.$image->id.'?variant=thumb')
            ->assertOk()->assertHeader('X-Aqer-DB-Queries','2');
        $this->assertNull($owner->apiTokens()->firstOrFail()->last_used_at);
        $property->forceFill(['status'=>'draft','review_status'=>'draft'])->save();
        $this->withToken($bearer)->get('/api/property-media/'.$image->id.'?variant=thumb')->assertOk();
        $this->assertNotNull($owner->apiTokens()->firstOrFail()->last_used_at);
        $this->flushHeaders();
        $this->get('/api/property-media/'.$image->id.'?variant=thumb')->assertNotFound();
    }

    public function test_production_does_not_expose_diagnostics_even_when_requested(): void
    {
        $this->app->detectEnvironment(fn () => 'production');
        $this->withHeader('X-Aqer-Diagnostics','perf-109')->getJson('/api/health')
            ->assertOk()->assertHeaderMissing('Server-Timing')->assertHeaderMissing('X-Aqer-DB-Queries');
    }

    public function test_storage_counters_keep_only_aggregate_values(): void
    {
        $metrics = new RequestPerformance;
        $metrics->storage(.12); $metrics->storage(.23); $metrics->query(10.5);
        $this->assertSame(2, $metrics->storageRequests);
        $this->assertEquals(350, $metrics->storageMs);
        $this->assertSame(1, $metrics->queries);
        $this->assertEquals(10.5, $metrics->databaseMs);
        $this->assertSame(['queries','databaseMs','storageRequests','storageMs'], array_keys(get_object_vars($metrics)));
    }

    public function test_private_verification_reads_download_once_after_authorization_and_preserve_auditing(): void
    {
        config(['services.supabase_storage.enabled'=>true,'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private','services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        \Illuminate\Support\Facades\Http::preventStrayRequests();
        \Illuminate\Support\Facades\Http::fake(['https://synthetic-storage.example/*'=>\Illuminate\Support\Facades\Http::sequence()
            ->push('synthetic-private',200,['Content-Type'=>'image/jpeg'])
            ->push('synthetic-private',200,['Content-Type'=>'image/jpeg'])->push('',404)]);
        $owner = User::create(['name'=>'Synthetic private owner','email'=>'private-performance@example.test','password'=>'unusable','account_status'=>'active','phone_verified_at'=>now()]);
        $other = User::create(['name'=>'Synthetic other','email'=>'other-performance@example.test','password'=>'unusable','account_status'=>'active','phone_verified_at'=>now()]);
        $profile = \App\Models\AccountVerificationProfile::create(['user_id'=>$owner->id,'type'=>'owner','status'=>'pending','details'=>[]]);
        $profile->documents()->create(['kind'=>'identity_document','path'=>'account_verification/synthetic.jpg','original_name'=>'synthetic.jpg','mime_type'=>'image/jpeg','size_bytes'=>17]);
        $owner->brokerVerificationDocuments()->create(['kind'=>'id_front','path'=>'broker_verification/synthetic.jpg','original_name'=>'synthetic.jpg','mime_type'=>'image/jpeg','size_bytes'=>17]);
        $tokens = app(\App\Services\ApiTokenService::class);
        $ownerBearer = $tokens->issue($owner, request())['plain_text_token'];
        $otherBearer = $tokens->issue($other, request())['plain_text_token'];
        foreach (['/api/account-verification/users/'.$owner->id.'/documents/identity_document',
                  '/api/broker/account-verification/users/'.$owner->id.'/documents/id_front'] as $url) {
            $this->withToken($otherBearer)->get($url)->assertForbidden();
            $this->withToken($ownerBearer)->get($url)->assertOk()->assertHeader('Cache-Control','no-store, private')->assertContent('synthetic-private');
        }
        \Illuminate\Support\Facades\Http::assertSentCount(2);
        $this->assertDatabaseHas('audit_logs',['action'=>'account.verification_document_viewed','actor_user_id'=>$owner->id]);
        $this->assertDatabaseHas('audit_logs',['action'=>'broker.account_verification_document_viewed','actor_user_id'=>$owner->id]);
        $this->withToken($ownerBearer)->get('/api/account-verification/users/'.$owner->id.'/documents/identity_document')->assertNotFound();
        $this->assertSame(2, DB::table('audit_logs')->whereIn('action',['account.verification_document_viewed','broker.account_verification_document_viewed'])->count());
    }
}
