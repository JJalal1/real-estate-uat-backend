<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\AdvertiserRating;
use App\Models\BrokerDealOutcome;
use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyPlatformReceivable;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use App\Models\SupportTask;
use App\Models\UserNotification;
use App\Services\BrokerDealService;
use App\Services\SupportTaskService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use App\Services\BrokerAvailabilityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class BrokerExperienceApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->startOfSecond());
    }

    public function test_availability_reminders_leave_overdue_listings_public_and_preserve_review_authority(): void
    {
        [$broker,$headers]=$this->actor('period',true);
        $sale=$this->listing($broker,'sale');
        $rent=$this->listing($broker,'rent');
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertTrue($sale->fresh()->availability_due_at->equalTo(now()->addDays(14)));
        $this->assertTrue($rent->fresh()->availability_due_at->equalTo(now()->addDays(7)));
        $this->travel(7)->days();
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertDatabaseHas('user_notifications',['user_id'=>$broker->id,'type'=>'broker_availability_due']);
        $this->assertTrue($rent->fresh()->isPubliclyAvailable());
        $this->travel(3)->days();
        app(BrokerAvailabilityService::class)->sweep();
        $this->assertSame('available', $rent->fresh()->availability_status);
        $this->assertTrue($rent->fresh()->isPubliclyAvailable());
        $this->getJson('/api/properties')->assertOk()->assertJsonFragment(['id'=>$rent->id]);
        $this->getJson('/api/properties/nearby?latitude=15.35&longitude=44.2')->assertOk()
            ->assertJsonFragment(['id'=>$rent->id]);
        $this->getJson('/api/properties/'.$rent->id)->assertOk()->assertJsonPath('data.id', $rent->id);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertOk()->assertJsonPath('data.active_listings', 2);
        $this->assertSame(1, DB::table('user_notifications')->where('user_id', $broker->id)
            ->where('type', 'broker_availability_due')->count());
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$sale->id,$rent->id],'state'=>'available'])
            ->assertOk()->assertJsonPath('data.updated',2);
        $this->assertTrue($rent->fresh()->isPubliclyAvailable());
        $rent->forceFill(['status'=>'draft','review_status'=>'returned_for_correction'])->saveQuietly();
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$rent->id],'state'=>'available'])->assertConflict();
        $this->assertSame('returned_for_correction',$rent->fresh()->review_status);
    }

    public function test_recovery_respects_manual_and_review_states_when_restoring_legacy_automatic_pauses(): void
    {
        [$broker, $headers] = $this->actor('restore-availability', true);
        $legacyPause = [
            'availability_status' => 'confirmation_paused',
            'availability_due_at' => now()->subDays(4),
            'availability_notified_at' => now()->subDays(3),
        ];
        $restorable = $this->listing($broker);
        $restorable->forceFill($legacyPause)->saveQuietly();
        $publishedAt = $restorable->published_at;
        $updatedAt = $restorable->updated_at;

        $protected = [];
        foreach ([
            ['availability_status' => 'paused'],
            ['availability_status' => 'sold'],
            ['availability_status' => 'rented', 'purpose' => 'rent'],
            ['status' => 'pending', 'review_status' => 'submitted'],
            ['status' => 'rejected', 'review_status' => 'rejected_blocked'],
            ['status' => 'archived'],
            ['financial_hold_at' => now()],
            ['availability_notified_at' => null],
            ['availability_due_at' => now()->addDay()],
        ] as $changes) {
            $listing = $this->listing($broker, $changes['purpose'] ?? 'sale');
            $listing->forceFill($changes + $legacyPause)->saveQuietly();
            $protected[] = $listing;
        }
        $assetId = DB::table('property_assets')->insertGetId([
            'identity_hash' => hash('sha256', 'availability-recovery-blocked'),
            'property_type' => 'apartment',
            'canonical_latitude' => 15.35,
            'canonical_longitude' => 44.2,
        ]);
        $blocked = $this->listing($broker);
        $blocked->forceFill($legacyPause + ['property_asset_id' => $assetId])->saveQuietly();
        DB::table('property_publication_blocks')->insert([
            'property_asset_id' => $assetId,
            'purpose' => $blocked->purpose,
            'is_active' => true,
            'reason' => 'Active publication block',
        ]);
        $protected[] = $blocked;

        app(BrokerAvailabilityService::class)->sweep();
        app(BrokerAvailabilityService::class)->sweep();
        $restorable->refresh();
        $this->assertSame('available', $restorable->availability_status);
        $this->assertTrue($restorable->published_at->equalTo($publishedAt));
        $this->assertTrue($restorable->updated_at->equalTo($updatedAt));
        $this->assertTrue($restorable->availability_notified_at->equalTo($legacyPause['availability_notified_at']));
        $this->assertTrue($restorable->availability_due_at->equalTo($legacyPause['availability_due_at']));
        $publicIds = array_column($this->getJson('/api/properties')->assertOk()->json('data'), 'id');
        $this->assertContains($restorable->id, $publicIds);
        foreach ($protected as $listing) {
            $fresh = $listing->fresh();
            $this->assertSame($listing->status, $fresh->status);
            $this->assertSame($listing->review_status, $fresh->review_status);
            $this->assertSame($listing->availability_status, $fresh->availability_status);
            $this->assertNotContains($listing->id, $publicIds);
        }
        $mine = $this->withHeaders($headers)->getJson('/api/properties/mine/list')->assertOk();
        $this->assertContains($protected[1]->id, array_column($mine->json('data'), 'id'));
        $this->assertContains($protected[2]->id, array_column($mine->json('data'), 'id'));
        $this->assertDatabaseMissing('user_notifications', ['user_id' => $broker->id, 'type' => 'broker_availability_due']);

        foreach ([$blocked, $protected[6]] as $held) {
            $this->postJson('/api/broker/listings/availability', [
                'property_ids' => [$held->id], 'state' => 'available',
            ])->assertConflict();
            $this->assertSame('confirmation_paused', $held->fresh()->availability_status);
        }
        $this->postJson('/api/broker/listings/availability', [
            'property_ids' => [$protected[0]->id], 'state' => 'available',
        ])->assertOk();
        $this->assertSame('available', $protected[0]->fresh()->availability_status);
    }

    public function test_owned_availability_pages_reach_beyond_the_legacy_250_row_cap(): void
    {
        [$broker,$headers]=$this->actor('availability-pages',true);
        [$other]=$this->actor('availability-pages-other',true);
        $first=$this->listing($broker);
        $first->forceFill(['availability_due_at'=>now()->addDay()])->saveQuietly();
        $rows=[];
        for ($i=0;$i<250;$i++) {
            $rows[]=['user_id'=>$broker->id,'title'=>'Synthetic availability '.$i,'purpose'=>'sale','type'=>'apartment',
                'price'=>100000,'currency'=>'YER','latitude'=>15.35,'longitude'=>44.2,'status'=>'published',
                'review_status'=>'approved','availability_status'=>'available','availability_due_at'=>now()->addDay(),
                'published_at'=>now(),'created_at'=>now(),'updated_at'=>now()];
        }
        Property::query()->insert($rows);
        $foreign=$this->listing($other);
        $foreign->forceFill(['availability_due_at'=>now()->subDay()])->saveQuietly();
        $this->listing($broker)->forceFill(['availability_status'=>'sold'])->saveQuietly();
        $this->listing($broker)->forceFill(['availability_status'=>'rented'])->saveQuietly();
        $this->listing($broker)->forceFill(['status'=>'draft'])->saveQuietly();
        $base='/api/broker/listings/availability';
        $this->withHeaders($headers)->getJson($base)->assertOk()->assertJsonCount(250,'data')
            ->assertJsonPath('meta.total',251)->assertJsonPath('meta.last_page',2);
        $ids=[];
        for ($page=1;$page<=6;$page++) {
            $response=$this->withHeaders($headers)->getJson($base.'?per_page=50&page='.$page)->assertOk()
                ->assertJsonPath('meta.current_page',$page)->assertJsonPath('meta.last_page',6)
                ->assertJsonCount($page===6 ? 1 : 50,'data');
            $ids=array_merge($ids,array_column($response->json('data'),'id'));
        }
        $this->assertCount(251,array_unique($ids));
        $expected=Property::query()->withoutGlobalScopes()->where('user_id',$broker->id)->where('status','published')
            ->where('availability_status','available')->orderBy('id')->pluck('id')->all();
        $this->assertSame($expected,$ids);
        $this->assertNotContains($foreign->id,$ids);
        $this->withHeaders($headers)->getJson($base.'?per_page=251')->assertUnprocessable();
        $this->withHeaders($headers)->getJson($base.'?page=0')->assertUnprocessable();
    }

    public function test_availability_due_filter_runs_before_pagination_and_preserves_ownership(): void
    {
        [$broker,$headers]=$this->actor('due-pages',true);
        [$other]=$this->actor('due-pages-other',true);
        $this->listing($broker)->forceFill(['availability_due_at'=>null])->saveQuietly();
        $this->listing($broker)->forceFill(['availability_due_at'=>now()->addDay()])->saveQuietly();
        $due=$this->listing($broker);
        $due->forceFill(['availability_due_at'=>now()->subDay()])->saveQuietly();
        $paused=$this->listing($broker);
        $paused->forceFill(['availability_due_at'=>now()->addDay(),'availability_status'=>'confirmation_paused'])->saveQuietly();
        $this->listing($other)->forceFill(['availability_due_at'=>now()->subDays(2)])->saveQuietly();
        $base='/api/broker/listings/availability?only_due=1&per_page=1&page=';
        $this->withHeaders($headers)->getJson($base.'1')->assertOk()->assertJsonPath('meta.total',1)
            ->assertJsonPath('data.0.id',$due->id)->assertJsonPath('data.0.needs_confirmation',true);
        $this->withHeaders($headers)->getJson($base.'2')->assertOk()->assertJsonPath('meta.last_page',1)
            ->assertJsonCount(0, 'data');
        $this->assertSame('confirmation_paused', $paused->fresh()->availability_status);
        $this->withHeaders($headers)->getJson('/api/broker/listings/availability?only_due=wrong')->assertUnprocessable();
    }

    public function test_bulk_update_is_atomic_and_rejects_foreign_listings(): void
    {
        [$broker,$headers]=$this->actor('own',true);
        [$other]=$this->actor('other',true);
        $own=$this->listing($broker);
        $foreign=$this->listing($other);
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$own->id,$foreign->id],'state'=>'available'])->assertForbidden();
        $this->withHeaders($headers)->postJson('/api/broker/listings/availability',['property_ids'=>[$own->id],'state'=>'paused'])->assertUnprocessable();
        $this->assertSame('available',$own->fresh()->availability_status);
        $this->assertSame('available',$foreign->fresh()->availability_status);
    }

    public function test_deal_result_reports_the_saved_listing_price_and_confirmed_sai(): void
    {
        [$broker, $brokerHeaders] = $this->actor('deal-result-prices', true);
        [, $buyerHeaders] = $this->actor('deal-result-buyer');
        $property = $this->listing($broker);
        $thread = $this->conversation($buyerHeaders, $property);
        $id = $this->withHeaders($brokerHeaders)->postJson('/api/broker/customers/'.$thread.'/completed-deal', [
            'basis_amount' => 82000,
        ])->assertCreated()->assertJsonPath('data.price_confirmation_required', true)
            ->assertJsonPath('data.status', 'pending_customer')->json('data.id');
        $url = '/api/broker/deals/'.$id;
        $this->flushHeaders()->getJson('/api/properties/'.$property->id)->assertOk();
        $this->assertDatabaseCount('property_platform_receivables', 0);

        // A later price edit must not change the original listing amount for this deal.
        $property->forceFill(['price' => 125000])->saveQuietly();
        $this->withHeaders($buyerHeaders)->postJson($url.'/decision', ['confirmed' => true])->assertOk();
        $this->flushHeaders()->getJson('/api/properties/'.$property->id)->assertNotFound();
        $this->withHeaders($brokerHeaders)->getJson($url)->assertOk()
            ->assertJsonPath('data.listing_price', 100000)
            ->assertJsonPath('data.listing_currency', 'YER')
            ->assertJsonPath('data.basis_amount', 82000)
            ->assertJsonPath('data.currency', 'YER')
            ->assertJsonPath('data.sai_amount', 1640)
            ->assertJsonPath('data.sai_currency', 'YER')
            ->assertJsonPath('data.sai_rate_percent', 2)
            ->assertJsonPath('data.sai_payment_status', null)
            ->assertJsonPath('data.confirmed_at', now()->toIso8601String());
    }

    public function test_equal_and_higher_reported_prices_close_the_listing_and_record_one_confirmed_deal(): void
    {
        [$broker, $brokerHeaders] = $this->actor('automatic-price-confirmation', true);
        [$customer, $customerHeaders] = $this->actor('automatic-price-buyer');
        foreach ([['sale', [], 100000], ['rent', ['basis_amount' => 100000], 100000],
            ['sale', ['basis_amount' => 120000], 120000]] as [$purpose, $input, $basis]) {
            $property = $this->listing($broker, $purpose);
            if ($purpose === 'rent') $property->forceFill(['price' => 900000])->saveQuietly();
            $thread = $this->conversation($customerHeaders, $property);
            $url = "/api/broker/customers/{$thread}/completed-deal";
            $dealId = $this->withHeaders($brokerHeaders)->postJson($url, $input)->assertCreated()
                ->assertJsonPath('data.status', 'confirmed')
                ->assertJsonPath('data.price_confirmation_required', false)
                ->assertJsonPath('data.listing_price', 100000)
                ->assertJsonPath('data.basis_amount', $basis)
                ->assertJsonPath('data.platform_due_status', 'pending_payment')->json('data.id');
            $this->withHeaders($brokerHeaders)->postJson($url, $input)->assertCreated()->assertJsonPath('data.id', $dealId);
            $this->flushHeaders()->getJson('/api/properties/'.$property->id)->assertNotFound();
            $this->assertSame($purpose === 'rent' ? 'rented' : 'sold', $property->fresh()->availability_status);
            $this->assertNull(BrokerDealOutcome::query()->findOrFail($dealId)->customer_confirmed_at);
            $this->assertDatabaseHas('user_notifications', ['user_id' => $customer->id, 'type' => 'broker_deal_result',
                'entity_id' => $dealId]);
            $this->assertDatabaseHas('property_deal_financial_terms', ['broker_deal_outcome_id' => $dealId, 'base_amount' => $basis]);
        }
        $this->assertDatabaseCount('broker_deal_outcomes', 3);
        $this->assertDatabaseCount('property_platform_receivables', 3);
        $this->assertDatabaseCount('support_cases', 0);
    }

    public function test_lower_price_has_one_support_task_contact_and_reminder_until_support_approves(): void
    {
        [$broker, $brokerHeaders] = $this->actor('support-price-broker', true);
        [$customer, $customerHeaders] = $this->actor('support-price-buyer');
        [$agent, $agentHeaders] = $this->actor('support-price-agent');
        [$outsider, $outsiderHeaders] = $this->actor('support-price-outsider');
        $agent->roles()->attach(Role::query()->where('key', 'support_agent')->value('id'));
        $property = $this->listing($broker, 'rent');
        $thread = $this->conversation($customerHeaders, $property);
        $otherThread = $this->conversation($outsiderHeaders, $property);
        $input = ['basis_amount' => 80000];
        $reportUrl = "/api/broker/customers/{$thread}/completed-deal";
        $response = $this->withHeaders($brokerHeaders)->postJson($reportUrl, $input)->assertCreated()
            ->assertJsonPath('data.status', 'pending_customer')->assertJsonPath('data.price_confirmation_required', true);
        $dealId = $response->json('data.id');
        $caseId = $response->json('data.support_case_id');
        $this->withHeaders($brokerHeaders)->postJson($reportUrl, $input)->assertCreated()->assertJsonPath('data.id', $dealId);
        $this->withHeaders($brokerHeaders)->postJson("/api/broker/customers/{$otherThread}/completed-deal", $input)->assertConflict();
        $this->flushHeaders()->getJson('/api/properties/'.$property->id)->assertOk();
        $this->assertDatabaseCount('property_platform_receivables', 0);
        $this->assertDatabaseHas('support_cases', ['id' => $caseId, 'target_id' => $dealId,
            'reason_code' => BrokerDealService::PRICE_CONFIRMATION_REASON, 'requester_user_id' => $customer->id]);
        $task = SupportTask::query()->where('source_type', 'support_ticket')->where('source_id', $caseId)->sole();
        $this->withHeaders($agentHeaders)->getJson('/api/admin/workspace/tasks?scope=inbox')->assertOk()
            ->assertJsonFragment(['id' => $task->id]);
        $resolution = '/api/broker/support/tasks/'.$task->id.'/resolution';
        $decision = ['decision' => 'approve', 'note' => 'أكد العميل الاتفاق على قيمة الإيجار'];
        $this->withHeaders($outsiderHeaders)->postJson($resolution, $decision)->assertForbidden();
        $this->withHeaders($agentHeaders)->postJson($resolution, $decision)->assertConflict();
        $this->withHeaders($agentHeaders)->postJson('/api/admin/workspace/tasks/'.$task->id.'/claim', [])->assertOk();
        $this->withHeaders($agentHeaders)->postJson('/api/admin/support/cases/'.$caseId.'/reply',
            ['body' => 'هل تؤكد مبلغ الإيجار المتفق عليه؟'])->assertOk();
        $this->withHeaders($customerHeaders)->getJson('/api/support/cases/'.$caseId)->assertOk()
            ->assertJsonFragment(['body' => 'هل تؤكد مبلغ الإيجار المتفق عليه؟']);

        $deals = app(BrokerDealService::class);
        $this->travel(23)->hours();
        $this->assertSame(0, $deals->remindSupportOfPendingPrices());
        $this->travel(1)->hours();
        $this->assertSame(1, $deals->remindSupportOfPendingPrices());
        $this->assertSame(0, $deals->remindSupportOfPendingPrices());
        $reminder = UserNotification::query()->where('user_id', $agent->id)->where('type', 'support_deal_confirmation_reminder')->sole();
        $this->assertEquals($task->id, $reminder->entity_id);
        $this->assertEquals($task->id, $reminder->data['task_id']);
        $this->assertEquals($dealId, $reminder->data['deal_id']);
        $this->assertDatabaseMissing('user_notifications', ['user_id' => $outsider->id, 'type' => 'support_deal_confirmation_reminder']);
        $this->assertDatabaseCount('support_cases', 1);
        $this->assertSame(1, SupportTask::query()->where('source_type', 'support_ticket')->where('source_id', $caseId)->count());

        $this->withHeaders($agentHeaders)->postJson($resolution, $decision)->assertOk()->assertJsonPath('data.status', 'confirmed');
        $this->withHeaders($agentHeaders)->postJson($resolution, $decision)->assertConflict();
        $this->assertSame('rented', $property->fresh()->availability_status);
        $this->assertDatabaseHas('broker_deal_outcomes', ['id' => $dealId, 'resolved_by_user_id' => $agent->id,
            'customer_confirmed_at' => null]);
        $this->assertDatabaseHas('property_deal_financial_terms', ['broker_deal_outcome_id' => $dealId, 'base_amount' => 80000]);
        $this->assertDatabaseHas('support_cases', ['id' => $caseId, 'status' => 'resolved']);
        $this->assertDatabaseCount('property_platform_receivables', 1);
    }

    public function test_two_party_result_unlocks_rating_and_freezes_existing_sai_without_an_agreement(): void
    {
        [$broker,$brokerHeaders]=$this->actor('confirmed',true);
        [$customer,$customerHeaders]=$this->actor('buyer');
        [, $outsiderHeaders]=$this->actor('outside');
        $property=$this->listing($broker);
        $property->forceFill(['price'=>120000])->saveQuietly();
        $thread=$this->conversation($customerHeaders,$property);
        $this->withHeaders($customerHeaders)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>5])->assertUnprocessable();
        $result=$this->withHeaders($brokerHeaders)->postJson('/api/broker/customers/'.$thread.'/completed-deal',['basis_amount'=>100000])->assertCreated();
        $id=(int)$result->json('data.id');
        $this->withHeaders($outsiderHeaders)->getJson('/api/broker/deals/'.$id)->assertNotFound();
        $this->withHeaders($brokerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertForbidden();
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->withHeaders($customerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk()->assertJsonPath('data.status','confirmed');
        $this->withHeaders($customerHeaders)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $this->assertDatabaseCount('broker_deal_outcomes',1);
        $this->assertDatabaseCount('property_agreements',0);
        $this->assertDatabaseCount('property_platform_receivables',1);
        $due=PropertyPlatformReceivable::query()->firstOrFail();
        $this->assertSame(500.0,$due->amount_total);
        $this->assertTrue($due->due_at->equalTo(now()->addHours(24)));
        config(['background.receivable_lead_minutes'=>1500]);
        $reminders = app(\App\Services\DeadlineReminderService::class);
        $reminders->receivables();
        $reminders->receivables();
        $notice = \App\Models\UserNotification::where('type', 'payment_due_reminder')->sole();
        $this->assertTrue($reminders->stillDue($notice));
        $due->update(['due_at'=>now()->addDays(2)]);
        $this->assertFalse($reminders->stillDue($notice));
        $due->update(['due_at'=>now()->addHours(24)]);
        $this->assertDatabaseHas('property_deal_financial_terms',['broker_deal_outcome_id'=>$id,'property_agreement_id'=>null,'buyer_user_id'=>$customer->id]);
        $this->withHeaders($customerHeaders)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>4])->assertCreated();
        $this->getJson('/api/advertisers/'.$broker->id.'/ratings/summary')->assertJsonPath('data.count',1)->assertJsonPath('data.average',4);
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/finance')->assertOk()->assertJsonPath('data.balances.0.open',500);
        $this->withHeaders($outsiderHeaders)->getJson('/api/broker/finance')->assertForbidden();
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/customers')->assertJsonPath('data.0.stage','completed');
    }

    public function test_denied_result_is_reviewable_but_never_counts_or_unlocks_rating(): void
    {
        [$broker,$bh]=$this->actor('disputed',true);
        [$customer,$ch]=$this->actor('deny');
        $property=$this->listing($broker);
        $thread=$this->conversation($ch,$property);
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',['basis_amount'=>90000])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk()->assertJsonPath('data.status','disputed');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertConflict();
        $this->withHeaders($ch)->putJson('/api/advertisers/'.$broker->id.'/rating',['rating'=>5])->assertUnprocessable();
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->assertDatabaseHas('support_cases',['target_type'=>'broker_deal_outcome','target_id'=>$id]);
        $this->flushHeaders()->getJson('/api/properties/'.$property->id)->assertOk();
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertJsonPath('data.completed_deals',0);
        $this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->assertJsonPath('data.id',$id);
        $this->assertDatabaseCount('broker_deal_outcomes',1);
    }

    public function test_an_existing_closed_listing_can_complete_its_legacy_pending_deal(): void
    {
        [$broker, $brokerHeaders] = $this->actor('legacy-deal-broker', true);
        [$customer, $customerHeaders] = $this->actor('legacy-deal-buyer');
        $property = $this->listing($broker);
        $thread = $this->conversation($customerHeaders, $property);
        $property->forceFill(['availability_status' => 'sold'])->saveQuietly();
        $legacyDeal = BrokerDealOutcome::query()->create([
            'reference' => 'DEAL-LEGACY-PRICE', 'property_id' => $property->id, 'message_thread_id' => $thread,
            'advertiser_user_id' => $broker->id, 'customer_user_id' => $customer->id,
            'sai_term_id' => $property->current_sai_term_id, 'status' => 'pending_customer',
            'transaction_type' => 'sale', 'basis_amount' => 100000, 'currency' => 'YER',
            'advertiser_confirmed_at' => now(),
            'snapshot' => ['record_kind' => 'external_transaction_result', 'property_title' => $property->title,
                'advertiser_name' => $broker->name, 'customer_name' => $customer->name],
        ]);
        $url = '/api/broker/deals/'.$legacyDeal->id;
        $this->withHeaders($brokerHeaders)->getJson($url)->assertOk()->assertJsonPath('data.price_confirmation_required', false);
        $this->travel(25)->hours();
        $this->assertSame(0, app(BrokerDealService::class)->remindSupportOfPendingPrices());
        $this->withHeaders($customerHeaders)->postJson($url.'/decision', ['confirmed' => true])->assertOk()
            ->assertJsonPath('data.status', 'confirmed');
        $this->assertSame('sold', $property->fresh()->availability_status);
        $this->assertDatabaseCount('property_platform_receivables', 1);
        $this->assertDatabaseCount('support_cases', 0);
    }

    public function test_directory_locality_public_privacy_and_legacy_ratings_are_not_verified_stars(): void
    {
        [$broker]=$this->actor('local',true,'صنعاء');
        [$other]=$this->actor('elsewhere',true,'عدن');
        [$rater]=$this->actor('legacy-rater');
        $this->listing($broker);$this->listing($other);
        AdvertiserRating::query()->create(['advertiser_user_id'=>$other->id,'advertiser_name_snapshot'=>$other->name,'rater_user_id'=>$rater->id,
            'rater_name_snapshot'=>$rater->name,'rating'=>5,'status'=>'visible']);
        $response=$this->getJson('/api/brokers?governorate='.urlencode('صنعاء'))->assertOk()->assertJsonPath('data.0.id',$broker->id);
        $response->assertJsonMissing(['email'=>$broker->email])->assertJsonMissing(['phone'=>$broker->phone]);
        $this->getJson('/api/advertisers/'.$other->id.'/profile')->assertJsonPath('data.rating_count',0)->assertJsonPath('data.rating_average',0);
        $this->assertDatabaseCount('advertiser_ratings',1);
    }

    public function test_views_are_explicit_and_deduplicated_and_read_notifications_leave_the_feed(): void
    {
        [$broker]=$this->actor('analytics',true);
        [, $customerHeaders]=$this->actor('reader');
        $property=$this->listing($broker);
        $this->getJson('/api/properties/'.$property->id)->assertOk();
        $this->assertSame(0,(int)$property->fresh()->view_count);
        $body=['viewer_key'=>'a-stable-test-viewer-123'];
        $this->withHeaders($customerHeaders)->postJson('/api/properties/'.$property->id.'/view',$body)->assertOk()->assertJsonPath('data.recorded',true);
        $this->withHeaders($customerHeaders)->postJson('/api/properties/'.$property->id.'/view',$body)->assertOk()->assertJsonPath('data.recorded',false);
        $this->assertSame(1,(int)$property->fresh()->view_count);
        $customerId=User::query()->where('email','reader@broker.test')->value('id');
        $notification=app(\App\Services\UserNotificationService::class)->create($customerId,'broker_test','Notification');
        $this->withHeaders($customerHeaders)->postJson('/api/notifications/'.$notification->id.'/read')->assertOk();
        $this->withHeaders($customerHeaders)->getJson('/api/notifications')->assertJsonCount(0,'data');
        $this->assertNotNull($notification->fresh()->read_at);
    }

    public function test_reminders_merge_across_batches_and_public_photo_is_separate_from_verification(): void
    {
        Storage::fake('public');
        Storage::fake('local');
        [$broker,$bh]=$this->actor('photos',true);
        [, $outsider]=$this->actor('photos-outside');
        $a=$this->listing($broker);$b=$this->listing($broker);
        $a->forceFill(['availability_due_at'=>now()->subHour()])->saveQuietly();
        $b->forceFill(['availability_due_at'=>now()->subHour()])->saveQuietly();
        app(BrokerAvailabilityService::class)->sweep(1);
        app(BrokerAvailabilityService::class)->sweep(1);
        $notices=DB::table('user_notifications')->where('type','broker_availability_due')->get();
        $this->assertCount(1,$notices);
        $this->assertSame(2,json_decode($notices->first()->data,true)['count']);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertJsonPath('data.photo_url',null);
        $this->get('/api/advertisers/'.$broker->id.'/photo')->assertNotFound();
        $this->withHeaders($outsider)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->image('photo.jpg')])->assertForbidden();
        $this->withHeaders($bh)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->image('public-photo.jpg')])->assertOk();
        $this->get('/api/advertisers/'.$broker->id.'/photo')->assertOk();
        $data=$this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertOk()->json('data');
        $this->assertStringContainsString('/api/advertisers/'.$broker->id.'/photo?v=',$data['photo_url']);
        $this->assertArrayNotHasKey('public_professional_photo_path',$data);
        $this->assertArrayNotHasKey('documents',$data);
    }

    public function test_claimed_support_can_retry_but_cannot_artificially_confirm_a_disputed_deal(): void
    {
        [$broker,$bh]=$this->actor('retry',true);
        [, $ch]=$this->actor('retry-client');
        [$agent,$ah]=$this->actor('retry-agent');
        [, $otherHeaders]=$this->actor('retry-other-agent');
        $role=Role::query()->where('key','support_agent')->firstOrFail();
        $agent->roles()->attach($role->id,['created_at'=>now()]);
        $permissions=DB::table('permissions')->where('key','support.handle_reports')->pluck('id');
        foreach ($permissions as $permission) DB::table('role_permission')->insertOrIgnore(['role_id'=>$role->id,'permission_id'=>$permission]);
        $thread=$this->conversation($ch,$this->listing($broker));
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',['basis_amount'=>95000])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk();
        $outcome=BrokerDealOutcome::query()->findOrFail($id);
        $task=SupportTask::query()->where('source_type','support_ticket')->where('source_id',$outcome->support_case_id)->firstOrFail();
        $url='/api/broker/support/tasks/'.$task->id.'/resolution';
        $this->withHeaders($otherHeaders)->postJson($url,['decision'=>'retry','note'=>'review request'])->assertForbidden();
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'review request'])->assertConflict();
        $this->withHeaders($ah)->postJson('/api/admin/workspace/tasks/'.$task->id.'/claim',[])->assertOk();
        $this->withHeaders($ah)->postJson($url,['decision'=>'confirmed','note'=>'review request'])->assertUnprocessable();
        $this->withHeaders($ah)->postJson($url,['decision'=>'approve','note'=>'review request'])->assertConflict();
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'العميل يحتاج إعادة تأكيد النتيجة'])->assertOk()->assertJsonPath('data.status','pending_customer');
        $this->assertDatabaseCount('property_platform_receivables',0);
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>false])->assertOk();
        $this->assertDatabaseCount('support_cases',1);
        $this->withHeaders($ah)->postJson($url,['decision'=>'retry','note'=>'أعيد طلب تأكيد النتيجة بعد مراجعة الطرفين'])->assertOk();
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $this->assertDatabaseCount('property_platform_receivables',1);
        $this->assertDatabaseHas('support_cases',['id'=>$outcome->support_case_id,'status'=>'resolved']);
    }

    public function test_receivable_payment_works_without_an_agreement_and_legacy_creation_is_dormant(): void
    {
        [$broker,$bh]=$this->actor('standalone-finance',true);
        [, $ch]=$this->actor('standalone-buyer');
        [, $oh]=$this->actor('standalone-outsider');
        $thread=$this->conversation($ch,$this->listing($broker));
        $this->withHeaders($ch)->postJson('/api/messages/threads/'.$thread.'/agreement',[])->assertStatus(410);
        $id=(int)$this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal',[])->assertCreated()->json('data.id');
        $this->withHeaders($ch)->postJson('/api/broker/deals/'.$id.'/decision',['confirmed'=>true])->assertOk();
        $due=PropertyPlatformReceivable::query()->firstOrFail();
        $this->withHeaders($oh)->getJson('/api/finance/receivables/'.$due->id)->assertForbidden();
        $this->withHeaders($bh)->getJson('/api/finance/receivables/'.$due->id)->assertOk()->assertJsonPath('data.agreement_id',null)->assertJsonPath('data.can_pay_full',false);
        $method=\App\Models\PropertyPaymentMethod::query()->create(['key'=>'broker-test-bank','name_ar'=>'وسيلة الاختبار','asset_key'=>'bank',
            'beneficiary_name'=>'اختبار','destination_label'=>'الحساب','destination_value'=>'TEST-ACCOUNT','currency'=>'YER',
            'min_amount'=>0,'max_amount'=>9999999,'allows_full_payment'=>false,'allows_sai_only'=>true,'is_enabled'=>true,'sort_order'=>100]);
        $this->withHeaders($bh)->postJson('/api/finance/receivables/'.$due->id.'/payments',['payment_method_id'=>$method->id])->assertCreated()->assertJsonPath('data.required_amount',500);
        $this->assertDatabaseHas('property_payments',['deal_financial_term_id'=>$due->deal_financial_term_id,'required_amount'=>500,'mode'=>'platform_receivable']);
        $this->assertDatabaseCount('property_agreements',0);
    }

    public function test_sale_and_rent_dues_keep_receipts_pending_until_review_and_restore_only_financial_holds(): void
    {
        config(['services.supabase_storage.enabled'=>false]);
        Storage::fake('local');
        [$broker, $brokerHeaders] = $this->actor('dues-sale-and-rent', true);
        [, $customerHeaders] = $this->actor('dues-customer');
        [$agent, $agentHeaders] = $this->actor('dues-support-agent');
        [$manager, $managerHeaders] = $this->actor('dues-support-manager');
        [$reviewer, $reviewerHeaders] = $this->actor('dues-reviewer');
        $agent->roles()->attach(Role::query()->where('key', 'support_agent')->value('id'));
        $manager->roles()->attach(Role::query()->where('key', 'support_manager')->value('id'));
        $reviewer->forceFill(['is_platform_owner'=>true])->saveQuietly();
        $sale = $this->listing($broker, 'sale');
        $rent = $this->listing($broker, 'rent');
        $other = $this->listing($broker);
        $paused = $this->listing($broker);
        $paused->forceFill([
            'availability_status'=>'paused','financial_hold_at'=>now(),'financial_hold_reason'=>'separate_admin_hold',
        ])->saveQuietly();
        $favorite = "/api/properties/{$other->id}/favorite";
        $this->withHeaders($customerHeaders)->putJson($favorite)->assertOk()
            ->assertJsonPath('data.is_favorited', true);

        $attempts = [];
        foreach ([$sale, $rent] as $property) {
            $thread = $this->conversation($customerHeaders, $property);
            $dealId = $this->withHeaders($brokerHeaders)->postJson("/api/broker/customers/$thread/completed-deal", [])
                ->assertCreated()->json('data.id');
            $this->withHeaders($customerHeaders)->postJson("/api/broker/deals/$dealId/decision", ['confirmed'=>true])
                ->assertOk()->assertJsonPath('data.status', 'confirmed');
            $due = PropertyPlatformReceivable::query()->where('property_id', $property->id)->sole();
            $this->assertTrue($due->due_at->equalTo($due->confirmed_direct_at->copy()->addHours(24)));
            $this->withHeaders($brokerHeaders)->getJson("/api/broker/deals/$dealId")
                ->assertOk()->assertJsonPath('data.platform_due_status', 'pending_payment');

            $methods = DB::table('property_payment_methods')->whereIn('key', ['jeeb','kuraimi'])->pluck('id', 'key');
            $endpoint = "/api/finance/receivables/{$due->id}/payments";
            $initial = $this->withHeaders($brokerHeaders)->postJson($endpoint, ['payment_method_id'=>$methods['jeeb']])
                ->assertCreated()->assertJsonPath('data.payment_method.key', 'jeeb')->json('data.id');
            $payment = $this->withHeaders($brokerHeaders)->postJson($endpoint, ['payment_method_id'=>$methods['kuraimi']])
                ->assertCreated()->assertJsonPath('data.payment_method.key', 'kuraimi')->json('data.id');
            $this->assertNotSame($initial, $payment);
            $this->assertDatabaseHas('property_payments', ['id'=>$initial,'status'=>'cancelled']);
            $this->withHeaders($brokerHeaders)->post("/api/finance/payments/$initial/proof", [
                'proof'=>UploadedFile::fake()->image('stale-proof.png'),
            ])->assertConflict();
            $this->withHeaders($brokerHeaders)->post("/api/finance/payments/$payment/proof", [
                'proof'=>UploadedFile::fake()->image('payment-proof.png'),
            ])->assertOk()->assertJsonPath('data.status', 'proof_submitted');
            $this->withHeaders($brokerHeaders)->postJson($endpoint, ['payment_method_id'=>$methods['jeeb']])->assertConflict();
            $this->withHeaders($brokerHeaders)->getJson("/api/broker/deals/$dealId")
                ->assertOk()->assertJsonPath('data.platform_due_status', 'pending_review');
            $attempts[] = [$due, $dealId, $payment];
        }
        [[$saleDue, $saleDeal, $salePayment], [$rentDue, $rentDeal]] = $attempts;
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/finance')->assertOk()
            ->assertJsonCount(2, 'data.receivables')
            ->assertJsonPath('data.balances.0.open', 1000)
            ->assertJsonPath('data.balances.0.paid', 0)
            ->assertJsonPath('data.receivables.0.transaction_type', 'rent')
            ->assertJsonPath('data.receivables.0.monthly_basis_amount', 100000)
            ->assertJsonPath('data.receivables.0.platform_due_status', 'pending_review');

        $nearby = '/api/properties/nearby?latitude=15.35&longitude=44.2';
        $narrowNearby = $nearby.'&radius_km=1';
        $this->travelTo($saleDue->due_at->copy()->subSecond());
        $this->flushHeaders()->getJson("/api/properties/{$other->id}")->assertOk();
        $this->getJson($nearby)->assertOk()->assertJsonFragment(['id'=>$other->id]);
        $this->travelTo($saleDue->due_at);
        $this->getJson("/api/properties/{$other->id}")->assertNotFound();
        $this->getJson('/api/properties')->assertOk()->assertJsonMissing(['id'=>$other->id]);
        $this->getJson($nearby)->assertOk()->assertJsonMissing(['id'=>$other->id]);
        $this->getJson($narrowNearby)->assertOk()->assertJsonMissing(['id'=>$other->id]);
        $this->getJson("/api/advertisers/{$broker->id}/profile")
            ->assertOk()->assertJsonPath('data.active_listings', 0);
        $this->withHeaders($customerHeaders)->getJson('/api/favorites')->assertOk()->assertJsonCount(0, 'data');
        $this->withHeaders($customerHeaders)->getJson('/api/favorites/ids')->assertOk()
            ->assertJsonPath('data.property_ids', []);
        $this->withHeaders($customerHeaders)->getJson($favorite)->assertNotFound();
        $this->withHeaders($customerHeaders)->putJson($favorite)->assertNotFound();
        $this->withHeaders($brokerHeaders)->getJson('/api/support/cases/mine')->assertOk();
        $this->withHeaders($brokerHeaders)->getJson("/api/finance/receivables/{$rentDue->id}")->assertOk();
        $this->withHeaders($brokerHeaders)->postJson('/api/properties')->assertConflict();

        $reviewUrl = "/api/admin/finance/payments/$salePayment/review";
        $this->withHeaders($reviewerHeaders)->postJson($reviewUrl, ['decision'=>'confirm'])
            ->assertOk()->assertJsonPath('data.status', 'confirmed');
        $this->withHeaders($reviewerHeaders)->postJson($reviewUrl, ['decision'=>'confirm'])->assertConflict();
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/finance')->assertOk()
            ->assertJsonCount(1, 'data.receivables')->assertJsonPath('data.receivables.0.id', $rentDue->id)
            ->assertJsonPath('data.balances.0.open', 500)->assertJsonPath('data.balances.0.paid', 500);
        for ($i=0; $i<2; $i++) {
            $activity = $this->withHeaders($brokerHeaders)->getJson('/api/broker/activity')->assertOk()
                ->assertJsonCount(2, 'data')->json('data');
            $byId = collect($activity)->keyBy('id');
            $this->assertSame('paid', $byId[$saleDeal]['platform_due_status']);
            $this->assertSame('pending_review', $byId[$rentDeal]['platform_due_status']);
        }
        $this->assertDatabaseHas('property_financial_holds', ['source_id'=>$rentDue->id,'released_at'=>null]);
        $this->flushHeaders()->getJson("/api/properties/{$other->id}")->assertNotFound();

        $context = "/api/admin/support/users/{$broker->id}";
        $restore = $context.'/financial-hold/restore';
        $reason = ['reason'=>'استعادة صلاحية الإعلان أثناء متابعة الإيصال'];
        $this->withHeaders($agentHeaders)->getJson($context)->assertOk()
            ->assertJsonPath('data.user.financial_hold_active', true)
            ->assertJsonPath('data.user.can_restore_financial_hold', false);
        $this->withHeaders($agentHeaders)->postJson($restore, $reason)->assertForbidden();
        $this->withHeaders($managerHeaders)->getJson($context)->assertOk()
            ->assertJsonPath('data.user.can_restore_financial_hold', true);
        $this->withHeaders($managerHeaders)->postJson($restore, $reason)->assertOk()
            ->assertJsonPath('data.restored_receivable_ids', [$rentDue->id]);
        $this->withHeaders($managerHeaders)->getJson($context)->assertOk()
            ->assertJsonPath('data.user.financial_hold_active', false);
        $this->assertDatabaseHas('audit_logs', ['action'=>'support.financial_hold_restored','actor_user_id'=>$manager->id,'target_user_id'=>$broker->id]);
        $this->assertDatabaseHas('property_platform_receivables', ['id'=>$rentDue->id,'amount_paid'=>0,'status'=>'overdue']);
        $this->assertSame('paused', $paused->fresh()->availability_status);
        $this->assertSame('separate_admin_hold', $paused->fresh()->financial_hold_reason);
        $this->withHeaders($brokerHeaders)->getJson('/api/broker/finance')->assertOk()
            ->assertJsonPath('data.policy.listing_creation_blocked', false);
        $this->flushHeaders()->getJson("/api/properties/{$other->id}")->assertOk();
        $this->getJson('/api/properties')->assertOk()->assertJsonFragment(['id'=>$other->id]);
        $this->getJson($nearby)->assertOk()->assertJsonFragment(['id'=>$other->id]);
        $this->getJson($narrowNearby)->assertOk()->assertJsonFragment(['id'=>$other->id]);
        $this->getJson("/api/properties?advertiser_id={$broker->id}")->assertOk()
            ->assertJsonFragment(['id'=>$other->id]);
        $this->getJson("/api/advertisers/{$broker->id}/profile")
            ->assertOk()->assertJsonPath('data.active_listings', 1);
        $this->withHeaders($customerHeaders)->getJson('/api/favorites')->assertOk()
            ->assertJsonPath('data.0.property.id', $other->id);
        $this->withHeaders($customerHeaders)->getJson('/api/favorites/ids')->assertOk()
            ->assertJsonPath('data.property_ids', [$other->id]);
        $this->withHeaders($customerHeaders)->getJson($favorite)->assertOk()
            ->assertJsonPath('data.is_favorited', true);
        $this->assertNull($other->fresh()->financial_hold_at);
    }

    public function test_customer_followup_is_private_owned_and_does_not_create_a_message(): void
    {
        [$broker,$bh]=$this->actor('followup-owner',true);
        [$customer,$ch]=$this->actor('followup-customer');
        [, $oh]=$this->actor('followup-outsider',true);
        $property=$this->listing($broker);
        $thread=$this->conversation($ch,$property);
        $url='/api/broker/customers/'.$thread.'/followup';
        $before=DB::table('private_messages')->count();
        $this->withHeaders($bh)->patchJson($url,['private_note'=>'ملاحظة خاصة لا تظهر للعميل','remind_at'=>now()->addDay()->toIso8601String()])->assertOk();
        $this->withHeaders($bh)->getJson($url)->assertOk()->assertJsonPath('data.private_note','ملاحظة خاصة لا تظهر للعميل');
        $this->withHeaders($oh)->getJson($url)->assertNotFound();
        $this->withHeaders($oh)->patchJson($url,['private_note'=>'changed'])->assertNotFound();
        $this->withHeaders($ch)->getJson($url)->assertForbidden();
        $this->withHeaders($ch)->getJson('/api/messages/threads/'.$thread)->assertOk()->assertJsonMissing(['private_note'=>'ملاحظة خاصة لا تظهر للعميل']);
        $this->getJson('/api/advertisers/'.$broker->id.'/profile')->assertOk()->assertJsonMissing(['private_note'=>'ملاحظة خاصة لا تظهر للعميل']);
        $this->assertSame($before,DB::table('private_messages')->count());
        $this->assertDatabaseCount('broker_customer_followups',1);
    }

    public function test_followup_reminder_is_once_reschedulable_and_can_be_completed(): void
    {
        [$broker,$bh]=$this->actor('followup-due',true);
        [$customer,$ch]=$this->actor('followup-due-customer');
        $thread=$this->conversation($ch,$this->listing($broker));
        $url='/api/broker/customers/'.$thread.'/followup';
        $this->withHeaders($bh)->patchJson($url,['private_note'=>'لا توضع في الإشعار','remind_at'=>now()->addMinutes(2)->toIso8601String()])->assertOk();
        $this->travel(3)->minutes();
        $service=app(\App\Services\BrokerCustomerFollowupService::class);
        $this->assertSame(1,$service->sweep());$this->assertSame(0,$service->sweep());
        $notice=DB::table('user_notifications')->where('type','broker_customer_followup_due')->first();
        $this->assertSame($broker->id,(int)$notice->user_id);
        $this->assertStringNotContainsString('لا توضع في الإشعار',$notice->body);
        $this->assertSame($thread,(int)$notice->entity_id);
        $this->withHeaders($bh)->getJson('/api/broker/customers?filter=followup_due')->assertOk()->assertJsonCount(1,'data');
        $this->withHeaders($bh)->patchJson($url,['private_note'=>'الملاحظة ما زالت خاصة'])->assertOk();
        $this->assertSame(0,$service->sweep());
        $this->withHeaders($bh)->patchJson($url,['remind_at'=>now()->addHour()->toIso8601String()])->assertOk();
        $this->assertNotNull(DB::table('user_notifications')->where('id',$notice->id)->value('read_at'));
        $this->travel(61)->minutes();$this->assertSame(1,$service->sweep());
        $this->withHeaders($bh)->patchJson($url,['remind_at'=>null])->assertOk()->assertJsonPath('data.private_note','الملاحظة ما زالت خاصة');
        $this->withHeaders($bh)->getJson('/api/broker/customers?filter=followup_due')->assertJsonCount(0,'data');
        $this->assertSame(0,$service->sweep());
        $this->assertSame(0,DB::table('user_notifications')->where('type','broker_customer_followup_due')->where('user_id',$customer->id)->count());
    }

    public function test_followup_validation_and_changed_ownership_preserve_private_records(): void
    {
        [$broker,$bh]=$this->actor('followup-invalid',true);
        [, $ch]=$this->actor('followup-invalid-customer');
        [$other]=$this->actor('followup-new-owner',true);
        $property=$this->listing($broker);$thread=$this->conversation($ch,$property);
        $url='/api/broker/customers/'.$thread.'/followup';
        $this->withHeaders($bh)->patchJson($url,['private_note'=>str_repeat('x',1501)])->assertUnprocessable();
        $this->withHeaders($bh)->patchJson($url,['remind_at'=>now()->subMinute()->toIso8601String()])->assertUnprocessable();
        $this->withHeaders($bh)->patchJson($url,['remind_at'=>now()->addYears(2)->toIso8601String()])->assertUnprocessable();
        $this->withHeaders($bh)->patchJson($url,['private_note'=>'تبقى خاصة','remind_at'=>now()->addMinute()->toIso8601String()])->assertOk();
        $property->forceFill(['user_id'=>$other->id])->saveQuietly();
        $this->travel(2)->minutes();
        $this->assertSame(0,app(\App\Services\BrokerCustomerFollowupService::class)->sweep());
        $this->withHeaders($bh)->getJson($url)->assertNotFound();
        $this->assertDatabaseHas('broker_customer_followups',['user_id'=>$broker->id,'private_note'=>'تبقى خاصة']);
    }

    public function test_unread_customer_shortcut_uses_the_server_read_marker(): void
    {
        [$broker,$bh]=$this->actor('unread-shortcut',true);
        [, $ch]=$this->actor('unread-shortcut-customer');
        $thread=$this->conversation($ch,$this->listing($broker));
        $this->withHeaders($ch)->postJson('/api/messages/threads/'.$thread.'/messages',['body'=>'أرغب بالمعاينة','client_message_id'=>'shortcut-message'])->assertCreated();
        $this->withHeaders($bh)->getJson('/api/broker/customers?filter=unread')->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.thread_id',$thread);
        $this->withHeaders($bh)->getJson('/api/messages/threads/'.$thread)->assertOk();
        $this->withHeaders($bh)->getJson('/api/broker/customers?filter=unread')->assertOk()->assertJsonCount(0,'data');
        $this->withHeaders($bh)->getJson('/api/broker/customers?filter=all')->assertJsonCount(1,'data');
    }

    public function test_customer_classification_is_explicit_private_and_scoped_to_listing(): void
    {
        [$broker, $bh] = $this->actor('classification-broker', true);
        [, $ch] = $this->actor('classification-customer');
        [, $oh] = $this->actor('classification-outsider', true);
        $saleThread = $this->conversation($ch, $this->listing($broker));
        $rent = $this->listing($broker, 'rent');
        $rentThread = $this->conversation($ch, $rent);
        $saleStage = '/api/broker/customers/'.$saleThread.'/stage';
        $rentStage = '/api/broker/customers/'.$rentThread.'/stage';

        $this->withHeaders($ch)->postJson('/api/messages/threads/'.$saleThread.'/messages', [
            'body' => 'أرغب في الاستفسار', 'client_message_id' => 'classification-first-message',
        ])->assertCreated();
        $this->assertDatabaseHas('message_threads', ['id' => $saleThread, 'lead_stage' => 'new', 'lead_updated_at' => null]);
        $this->withHeaders($bh)->patchJson($rentStage, ['stage' => 'viewing'])->assertOk();
        $this->withHeaders($bh)->getJson('/api/broker/customers?stage=unclassified')->assertOk()
            ->assertJsonPath('meta.customer_stage_classification_v2', true)->assertJsonCount(2, 'data');
        $this->withHeaders($oh)->patchJson($saleStage, ['stage' => 'reserved'])->assertNotFound();
        $this->withHeaders($bh)->patchJson($saleStage, ['stage' => 'completed'])->assertUnprocessable();
        $this->withHeaders($bh)->patchJson($saleStage, ['stage' => 'appointment_set'])->assertOk()
            ->assertJsonPath('data.stage', 'appointment_set');
        $this->withHeaders($bh)->patchJson($rentStage, ['stage' => 'reserved'])->assertOk()
            ->assertJsonPath('data.stage', 'reserved');
        $this->withHeaders($bh)->getJson('/api/broker/customers?stage=reserved')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.thread_id', $rentThread);
        $this->withHeaders($bh)->getJson('/api/messages/threads/'.$rentThread)->assertOk()
            ->assertJsonPath('data.thread.customer_stage_classification_v2', true)
            ->assertJsonPath('data.thread.lead_stage', 'reserved');
        $this->withHeaders($ch)->getJson('/api/messages/threads/'.$rentThread)->assertOk()
            ->assertJsonPath('data.thread.customer_stage_classification_v2', false)
            ->assertJsonPath('data.thread.lead_stage', 'new');
        $this->assertDatabaseHas('properties', ['id' => $rent->id, 'availability_status' => 'available']);
        $this->assertDatabaseCount('broker_deal_outcomes', 0);
        $this->withHeaders($bh)->patchJson($saleStage, ['stage' => 'new'])->assertOk();
        $this->withHeaders($bh)->getJson('/api/broker/customers?stage=unclassified')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.thread_id', $saleThread);
    }

    public function test_customer_rows_report_latest_actual_message_and_direction_without_marking_it_read(): void
    {
        [$broker, $bh] = $this->actor('message-preview-broker', true);
        [$customer, $ch] = $this->actor('message-preview-customer');
        [, $outsider] = $this->actor('message-preview-outsider', true);
        $thread = $this->conversation($ch, $this->listing($broker));
        $messages = "/api/messages/threads/$thread/messages";
        $customers = '/api/broker/customers';

        $this->withHeaders($bh)->getJson($customers)->assertOk()
            ->assertJsonPath('data.0.last_message_preview', null)
            ->assertJsonPath('data.0.last_message_at', null)
            ->assertJsonPath('data.0.last_message_is_mine', false)
            ->assertJsonPath('data.0.unread_count', 0);
        $incoming = $this->withHeaders($ch)->postJson($messages, ['body' => 'هل العقار متاح؟'])
            ->assertCreated()->json('data.created_at');
        $this->withHeaders($bh)->getJson($customers)->assertOk()
            ->assertJsonPath('data.0.last_message_preview', 'هل العقار متاح؟')
            ->assertJsonPath('data.0.last_message_at', $incoming)
            ->assertJsonPath('data.0.last_message_is_mine', false)
            ->assertJsonPath('data.0.unread_count', 1);

        $reply = str_repeat('ن', 130);
        $outgoing = $this->withHeaders($bh)->postJson($messages, ['body' => $reply])
            ->assertCreated()->json('data.created_at');
        DB::table('private_messages')->insert([
            'thread_id' => $thread,
            'sender_user_id' => $customer->id,
            'sender_name_snapshot' => $customer->name,
            'client_message_id' => 'sys-call:preview-test',
            'body' => 'System call event',
            'created_at' => now()->addSecond(),
        ]);
        $this->withHeaders($bh)->getJson($customers)->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.last_message_preview', mb_substr($reply, 0, 120))
            ->assertJsonPath('data.0.last_message_at', $outgoing)
            ->assertJsonPath('data.0.last_message_is_mine', true)
            ->assertJsonPath('data.0.unread_count', 2);
        $this->withHeaders($outsider)->getJson($customers)->assertOk()->assertJsonCount(0, 'data');
        $this->withHeaders($bh)->getJson("/api/messages/threads/$thread")->assertOk();
        $this->withHeaders($bh)->getJson($customers)->assertOk()->assertJsonPath('data.0.unread_count', 0);
    }

    public function test_opt_in_inbox_includes_other_participant_threads_without_crm_details(): void
    {
        [$broker, $bh] = $this->actor('inbox-managed-broker', true);
        [$customer, $ch] = $this->actor('inbox-direct-customer');
        [$owner, $oh] = $this->actor('inbox-other-owner', true);
        [, $xh] = $this->actor('inbox-private-outsider');
        $brokerProperty = $this->listing($broker);
        $otherProperty = $this->listing($owner);
        $owned = $this->conversation($ch, $brokerProperty);
        $direct = $this->withHeaders($ch)->postJson("/api/brokers/{$broker->id}/conversation")
            ->assertCreated()->json('data.id');
        $outbound = $this->conversation($bh, $otherProperty);
        $unrelated = $this->conversation($xh, $otherProperty);
        $this->withHeaders($bh)->patchJson("/api/broker/customers/$owned/stage", ['stage' => 'reserved'])->assertOk();
        $this->withHeaders($oh)->patchJson("/api/broker/customers/$outbound/stage", ['stage' => 'reserved'])->assertOk();
        $this->withHeaders($oh)->patchJson("/api/broker/customers/$outbound/followup", [
            'private_note' => 'Private note from the other property owner',
        ])->assertOk();
        $this->withHeaders($oh)->postJson("/api/messages/threads/$outbound/messages", [
            'body' => 'رد مالك العقار الآخر',
        ])->assertCreated();
        $customers = '/api/broker/customers';
        $this->withHeaders($bh)->getJson($customers)->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.thread_id', $owned);

        $all = $this->withHeaders($bh)->getJson($customers.'?include_other_threads=1')->assertOk()
            ->assertJsonCount(3, 'data')->assertJsonPath('data.0.thread_id', $owned)
            ->assertJsonPath('data.0.can_manage_customer', true)
            ->assertJsonPath('data.0.stage', 'reserved')
            ->assertJsonMissing(['thread_id' => $unrelated]);
        $rows = collect($all->json('data'))->keyBy('thread_id');
        $this->assertSame($owner->name, $rows[$outbound]['customer_name']);
        $this->assertSame($customer->name, $rows[$direct]['customer_name']);
        $this->assertSame('رد مالك العقار الآخر', $rows[$outbound]['last_message_preview']);
        foreach ([$direct, $outbound] as $threadId) {
            $this->assertFalse($rows[$threadId]['can_manage_customer']);
            foreach (['stage', 'followup', 'deal'] as $private) {
                $this->assertNull($rows[$threadId][$private]);
            }
        }

        $this->withHeaders($bh)->getJson($customers.'?include_other_threads=1&stage=unclassified')->assertOk()
            ->assertJsonCount(2, 'data')->assertJsonMissing(['thread_id' => $owned]);
        $this->withHeaders($bh)->getJson($customers.'?include_other_threads=1&stage=reserved')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.thread_id', $owned);
        $this->withHeaders($bh)->getJson($customers.'?include_other_threads=1&property_id='.$brokerProperty->id)->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.thread_id', $owned);
    }

    public function test_deal_view_only_clears_the_revision_seen_by_the_advertiser(): void
    {
        [$broker, $bh] = $this->actor('unseen-broker', true);
        [, $ch] = $this->actor('unseen-customer');
        [, $oh] = $this->actor('unseen-outsider', true);
        $thread = $this->conversation($ch, $this->listing($broker));
        $dealId = $this->withHeaders($bh)->postJson('/api/broker/customers/'.$thread.'/completed-deal', ['basis_amount' => 90000])
            ->assertCreated()->json('data.id');
        $url = '/api/broker/deals/'.$dealId;
        $this->withHeaders($bh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.capabilities.broker_deal_view_tracking', true)
            ->assertJsonPath('data.needs_attention.unseen_deal_count', 1)
            ->assertJsonPath('data.needs_attention.outstanding_receivables_count', 0)
            ->assertJsonPath('data.achievements.first_confirmed_deal', false);
        $this->withHeaders($oh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.needs_attention.unseen_deal_count', 0);
        $this->withHeaders($ch)->getJson($url)->assertOk()->assertJsonPath('data.advertiser_view_revision', null);
        $this->withHeaders($ch)->postJson($url.'/seen', ['revision' => 1])->assertNotFound();
        $this->withHeaders($bh)->getJson($url)->assertOk()->assertJsonPath('data.advertiser_view_revision', 1);
        $this->withHeaders($bh)->postJson($url.'/seen', ['revision' => 1])->assertNoContent();
        $this->withHeaders($bh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.needs_attention.unseen_deal_count', 0);

        $this->withHeaders($ch)->postJson($url.'/decision', ['confirmed' => true])->assertOk();
        $this->withHeaders($bh)->postJson($url.'/seen', ['revision' => 1])->assertNoContent();
        $this->withHeaders($bh)->getJson($url)->assertOk()->assertJsonPath('data.advertiser_view_revision', 2);
        $this->withHeaders($bh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.needs_attention.unseen_deal_count', 1)
            ->assertJsonPath('data.needs_attention.outstanding_receivables_count', 1)
            ->assertJsonPath('data.achievements.first_confirmed_deal', true);
        $this->withHeaders($bh)->postJson($url.'/seen', ['revision' => 2])->assertNoContent();
        $this->withHeaders($bh)->postJson($url.'/seen', ['revision' => 2])->assertNoContent();
        $this->withHeaders($bh)->getJson($url)->assertOk()->assertJsonPath('data.advertiser_view_revision', null);
        $this->withHeaders($bh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.needs_attention.unseen_deal_count', 0);
    }

    public function test_achievements_count_actual_inquiries_and_unique_replied_customers(): void
    {
        $this->travelTo(now('Asia/Aden')->setDate(2026, 11, 10)->setTime(12, 0)->utc());
        [$broker, $bh] = $this->actor('achievements-broker', true);
        [, $ch] = $this->actor('achievements-customer');
        [, $oh] = $this->actor('achievements-other');
        $sale = $this->listing($broker);
        $rent = $this->listing($broker, 'rent');
        $saleThread = $this->conversation($ch, $sale);
        $rentThread = $this->conversation($ch, $rent);
        $oldThread = $this->conversation($oh, $sale);
        $this->conversation($oh, $rent);

        foreach ([$saleThread, $rentThread] as $thread) {
            $url = '/api/messages/threads/'.$thread.'/messages';
            $this->withHeaders($ch)->postJson($url, [
                'body' => 'هل العقار متاح؟', 'client_message_id' => 'achievement-inquiry-'.$thread,
            ])->assertCreated();
            $this->withHeaders($bh)->postJson($url, [
                'body' => 'العقار متاح', 'client_message_id' => 'achievement-reply-'.$thread,
            ])->assertCreated();
        }
        $oldUrl = '/api/messages/threads/'.$oldThread.'/messages';
        $this->withHeaders($oh)->postJson($oldUrl, [
            'body' => 'استفسار قديم', 'client_message_id' => 'achievement-earlier-inquiry',
        ])->assertCreated();
        DB::table('private_messages')->where('thread_id', $oldThread)->update(['created_at' => now()->subMonth()]);
        $this->withHeaders($oh)->postJson($oldUrl, [
            'body' => 'متابعة الاستفسار السابق', 'client_message_id' => 'achievement-earlier-followup',
        ])->assertCreated();

        $this->withHeaders($bh)->getJson('/api/broker/workspace')->assertOk()
            ->assertJsonPath('data.achievements.customers_replied_to_this_week', 1)
            ->assertJsonPath('data.achievements.listing_inquiries_this_month', 2)
            ->assertJsonPath('data.achievements.customer_ratings_count', 0);
    }

    public function test_retired_broker_viewing_lists_preserve_both_legacy_rows_without_exposing_them(): void
    {
        [$broker,$bh]=$this->actor('daily-viewings',true);
        [$customer,$ch]=$this->actor('daily-viewings-customer');
        [, $oh]=$this->actor('daily-viewings-outside');
        $property=$this->listing($broker);
        foreach ([['today',now()->startOfDay()->addHours(10)],['next-day',now()->addDay()->startOfDay()->addHours(10)]] as [$ref,$date]) {
            \App\Models\ViewingBooking::query()->create(['reference'=>'DAILY-'.$ref,'target_type'=>'property','target_id'=>$property->id,'target_title_snapshot'=>$property->title,
                'requester_user_id'=>$customer->id,'requester_name_snapshot'=>$customer->name,'host_user_id'=>$broker->id,'host_name_snapshot'=>$broker->name,
                'starts_at'=>$date,'ends_at'=>$date->copy()->addHour(),'timezone'=>'Asia/Aden','status'=>'confirmed']);
        }
        $query=http_build_query(['starts_from'=>now()->startOfDay()->toIso8601String(),'starts_before'=>now()->addDay()->startOfDay()->toIso8601String()]);
        foreach ([$bh,$ch,$oh] as $headers) {
            $this->withHeaders($headers)->getJson('/api/bookings/mine?'.$query)->assertStatus(410);
            $this->withHeaders($headers)->getJson('/api/bookings/mine')->assertStatus(410);
        }
        $this->assertDatabaseCount('viewing_bookings',2);
        $this->assertDatabaseHas('viewing_bookings',['reference'=>'DAILY-today','status'=>'confirmed']);
        $this->assertDatabaseHas('viewing_bookings',['reference'=>'DAILY-next-day','status'=>'confirmed']);
    }

    private function actor(string $key, bool $professional=false, string $governorate='صنعاء'): array
    {
        $user=User::query()->create(['name'=>'Broker Test '.$key,'email'=>$key.'@broker.test','phone'=>'+9677'.substr(hash('crc32b',$key),0,8),
            'phone_verified_at'=>now(),'profile_completed_at'=>now(),'account_status'=>'active','password'=>Hash::make('broker-test-password')]);
        $role=Role::query()->where('key','registered_user')->firstOrFail();
        $user->roles()->attach($role->id,['assigned_by_user_id'=>null,'created_at'=>now()]);
        if ($professional) AccountVerificationProfile::query()->create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','reviewed_at'=>now(),
            'details'=>['governorate'=>$governorate,'work_areas'=>[$governorate]]]);
        $token='broker_'.hash('sha256',$key);
        $user->apiTokens()->create(['name'=>'broker-test','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addYear()]);
        return [$user,['Authorization'=>'Bearer '.$token,'Accept'=>'application/json']];
    }

    private function listing(User $broker, string $purpose='sale'): Property
    {
        $p=Property::query()->create(['user_id'=>$broker->id,'title'=>'Broker listing '.$purpose,'purpose'=>$purpose,'type'=>'apartment',
            'price'=>100000,'monthly_rent'=>$purpose==='rent' ? 100000 : null,'currency'=>'YER','latitude'=>15.35,'longitude'=>44.2,
            'status'=>'published','review_status'=>'approved','published_at'=>now()]);
        $sai=PropertySaiTerm::query()->create(['property_id'=>$p->id,'version'=>1,'advertiser_type'=>'broker','purpose'=>$purpose,
            'source_mode'=>'broker_custom','requested_broker_rate_percent'=>2,'sai_rate_percent'=>2,'payer'=>$purpose==='rent' ? 'landlord' : 'seller',
            'calculation_basis'=>$purpose==='rent' ? 'first_month_rent' : 'final_sale_value','platform_share_percent'=>25,'broker_share_percent'=>75,
            'platform_terms_status'=>'accepted','platform_terms_accepted_at'=>now(),'created_by_user_id'=>$broker->id]);
        $p->forceFill(['current_sai_term_id'=>$sai->id])->saveQuietly();
        return $p;
    }

    private function conversation(array $headers, Property $property): int
    {
        return (int)$this->withHeaders($headers)->postJson('/api/properties/'.$property->id.'/conversation',[])->assertCreated()->json('data.id');
    }
}
