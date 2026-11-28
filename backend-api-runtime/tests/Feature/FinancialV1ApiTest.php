<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPayment;
use App\Models\PropertyPaymentMethod;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\SupportTask;
use App\Models\User;
use App\Services\FinancialSupportTaskService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use App\Services\PropertyFinancialService;
use App\Services\SupportTaskService;
use Tests\TestCase;

class FinancialV1ApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['broker_experience.legacy_contract_creation'=>true]);
    }

    public function test_financial_routes_require_authentication(): void
    {
        $this->getJson('/api/finance/payments/mine')->assertUnauthorized();
        $this->getJson('/api/finance/account')->assertUnauthorized();
        $this->getJson('/api/admin/finance/summary')->assertUnauthorized();
    }

    public function test_support_roles_receive_payment_review_without_finance_management(): void
    {
        $reviewId = DB::table('permissions')->where('key', 'payments.review')->value('id');
        $viewId = DB::table('permissions')->where('key', 'finance.view')->value('id');
        $manageId = DB::table('permissions')->where('key', 'finance.manage')->value('id');

        foreach (['support_agent', 'support_manager'] as $roleKey) {
            $roleId = DB::table('roles')->where('key', $roleKey)->value('id');
            $this->assertDatabaseHas('role_permission', ['role_id'=>$roleId, 'permission_id'=>$reviewId]);
            $this->assertDatabaseMissing('role_permission', ['role_id'=>$roleId, 'permission_id'=>$viewId]);
            $this->assertDatabaseMissing('role_permission', ['role_id'=>$roleId, 'permission_id'=>$manageId]);
        }
    }

    public function test_accepted_agreement_freezes_financial_terms_once(): void
    {
        [$agreementId, $property, $advertiser, $buyer, $advertiserHeaders, $buyerHeaders] = $this->acceptedSaleDeal('buyer');

        $this->assertDatabaseCount('property_deal_financial_terms', 1);
        $this->assertDatabaseHas('property_deal_financial_terms', [
            'property_agreement_id'=>$agreementId,
            'property_id'=>$property->id,
            'buyer_user_id'=>$buyer->id,
            'advertiser_user_id'=>$advertiser->id,
            'transaction_type'=>'sale',
            'sai_payer'=>'buyer',
            'base_amount'=>90_000_000,
            'sai_total_amount'=>900_000,
            'platform_share_amount'=>900_000,
        ]);

        $revisionId = (int) DB::table('property_agreement_revisions')->where('property_agreement_id', $agreementId)->value('id');
        $this->withHeaders($advertiserHeaders)->postJson("/api/agreements/$agreementId/accept", ['revision_id'=>$revisionId])->assertOk();
        $this->assertDatabaseCount('property_deal_financial_terms', 1);

        $this->withHeaders($buyerHeaders)->getJson("/api/finance/agreements/$agreementId")
            ->assertOk()
            ->assertJsonPath('data.base_amount', 90000000)
            ->assertJsonPath('data.sai_total_amount', 900000)
            ->assertJsonPath('data.required_full_payment', 90900000);
    }

    public function test_public_property_uses_financial_price_display_without_internal_split(): void
    {
        [$advertiser] = $this->user('financial-price-owner@example.test', '+967772000011');
        $property = $this->property($advertiser, 100_000_000, 'Financial public price');
        $term = $this->term($property, 'buyer');
        $property->forceFill(['current_sai_term_id'=>$term->id, 'price_display_mode'=>'includes_sai'])->save();

        $this->flushHeaders();
        $this->getJson("/api/properties/{$property->id}")
            ->assertOk()
            ->assertJsonPath('data.base_price', 100000000)
            ->assertJsonPath('data.display_price', 101000000)
            ->assertJsonPath('data.price_display_note', 'المبلغ شامل السعي')
            ->assertJsonPath('data.sai.amount', 1000000)
            ->assertJsonMissingPath('data.platform_share_amount')
            ->assertJsonMissingPath('data.advertiser_sai_share_amount');
    }

    public function test_direct_deal_creates_24_hour_receivable_and_keeps_listings_available_after_deadline(): void
    {
        [$agreementId, $property, $advertiser, , $advertiserHeaders, $buyerHeaders] = $this->acceptedSaleDeal('seller');

        $this->withHeaders($buyerHeaders)
            ->postJson("/api/finance/agreements/$agreementId/direct-confirmation", ['decision'=>'confirmed'])
            ->assertOk()->assertJsonPath('data.completed', false);

        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/finance/agreements/$agreementId/direct-confirmation", ['decision'=>'confirmed'])
            ->assertOk()->assertJsonPath('data.completed', true);

        $receivable = DB::table('property_platform_receivables')->where('advertiser_user_id', $advertiser->id)->first();
        $this->assertNotNull($receivable);
        $this->assertSame('open', $receivable->status);
        $this->assertEquals(900000.0, (float) $receivable->amount_total);
        $this->assertTrue(now()->diffInMinutes(\Carbon\Carbon::parse($receivable->due_at), false) >= 1439);
        $this->assertDatabaseMissing('property_financial_holds', [
            'user_id'=>$advertiser->id,
            'reason'=>'platform_receivable_open',
            'source_id'=>$receivable->id,
        ]);
        $this->assertDatabaseHas('property_financial_ledger_entries', [
            'entry_type'=>'platform_receivable_created',
            'source_type'=>'property_platform_receivable',
            'source_id'=>$receivable->id,
        ]);

        $this->withHeaders($advertiserHeaders)
            ->postJson('/api/properties', [])
            ->assertUnprocessable();

        $this->flushHeaders();
        $this->getJson("/api/properties/{$property->id}")->assertOk();

        DB::table('property_platform_receivables')->where('id', $receivable->id)->update([
            'due_at'=>now()->subMinute(),
            'updated_at'=>now(),
        ]);
        $this->getJson("/api/properties/{$property->id}")->assertOk();
        $this->getJson('/api/properties')
            ->assertOk()
            ->assertJsonFragment(['id'=>$property->id]);

        $this->withHeaders($advertiserHeaders)
            ->getJson('/api/properties/mine/list')
            ->assertOk()
            ->assertJsonFragment(['id'=>$property->id]);
        $this->assertDatabaseHas('properties', ['id'=>$property->id, 'status'=>'published']);
    }

    public function test_rental_financial_configuration_is_complete_and_snapshotted_on_listing(): void
    {
        [$advertiser, $headers] = $this->user('financial-rent-owner@example.test', '+967772000041');
        $property = $this->property($advertiser, 1_000_000, 'Financial rent config');
        $property->forceFill(['purpose'=>'rent','status'=>'draft','review_status'=>'draft','published_at'=>null])->saveQuietly();

        $this->withHeaders($headers)->patchJson("/api/properties/{$property->id}/financial-config", [
            'monthly_rent'=>250000,
            'rental_term_months'=>12,
            'advance_months'=>3,
            'price_display_mode'=>'excludes_sai',
        ])->assertOk()
          ->assertJsonPath('data.price', 750000)
          ->assertJsonPath('data.monthly_rent', 250000)
          ->assertJsonPath('data.rental_term_months', 12)
          ->assertJsonPath('data.advance_months', 3);

        $this->assertDatabaseHas('properties', [
            'id'=>$property->id,'purpose'=>'rent','price'=>750000,
            'monthly_rent'=>250000,'rental_term_months'=>12,'advance_months'=>3,
            'price_display_mode'=>'excludes_sai',
        ]);
        $this->withHeaders($headers)->patchJson("/api/properties/{$property->id}/financial-config", [
            'monthly_rent'=>250000,'rental_term_months'=>2,'advance_months'=>3,
        ])->assertStatus(422);
    }

    public function test_advertiser_can_submit_a_private_receipt_without_sender_details_and_reopen_the_receivable(): void
    {
        config(['services.supabase_storage.enabled' => false]);
        Storage::fake('local');
        Storage::fake('public');

        [$agreementId, , , , $advertiserHeaders, $buyerHeaders] = $this->acceptedSaleDeal('seller');
        $confirmation = "/api/finance/agreements/$agreementId/direct-confirmation";
        $this->withHeaders($buyerHeaders)->postJson($confirmation, ['decision' => 'confirmed'])->assertOk();
        $dueId = $this->withHeaders($advertiserHeaders)
            ->postJson($confirmation, ['decision' => 'confirmed'])
            ->assertOk()->json('data.receivable.id');
        $receivablePath = "/api/finance/receivables/$dueId";

        $wallet = PropertyPaymentMethod::query()->where('key', 'jeeb')->firstOrFail();
        $this->assertTrue($wallet->requires_sender_phone);
        PropertyPaymentMethod::query()->where('key', 'kuraimi')->update(['allows_sai_only' => false]);

        $detail = $this->getJson($receivablePath)
            ->assertOk()
            ->assertJsonPath('data.receivable.id', $dueId)
            ->assertJsonPath('data.receivable.remaining_amount', 900_000)
            ->assertJsonPath('data.can_pay_full', false)
            ->assertJsonCount(0, 'data.payments');
        $methods = collect($detail->json('data.payment_methods'))->keyBy('key');
        $this->assertTrue($methods['jeeb']['available']);
        $this->assertFalse($methods['kuraimi']['available']);
        $this->withHeaders($buyerHeaders)->getJson($receivablePath)->assertForbidden();

        $legacyPaymentId = $this->withHeaders($advertiserHeaders)
            ->postJson("/api/finance/agreements/$agreementId/payments", [
                'mode' => 'platform_sai_only',
                'payment_method_id' => $wallet->id,
            ])->assertCreated()->json('data.id');
        $paymentId = $this->postJson($receivablePath.'/payments', ['payment_method_id' => $wallet->id])
            ->assertCreated()
            ->assertJsonPath('data.required_amount', 900_000)
            ->json('data.id');
        $this->assertNotSame($legacyPaymentId, $paymentId);
        $receipt = fn (): UploadedFile => UploadedFile::fake()->createWithContent(
            'receipt.png',
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP1EAAAAASUVORK5CYII='),
        );
        $proofPath = "/api/finance/payments/$paymentId/proof";
        $this->post("/api/finance/payments/$legacyPaymentId/proof", ['proof' => $receipt()])
            ->assertUnprocessable()->assertJsonValidationErrors('sender_phone');
        $this->post($proofPath, [])
            ->assertUnprocessable()->assertJsonValidationErrors('proof');
        $this->post($proofPath, ['proof' => $receipt()])
            ->assertOk()
            ->assertJsonPath('data.status', 'proof_submitted')
            ->assertJsonPath('data.sender_name', null)
            ->assertJsonPath('data.sender_phone', null)
            ->assertJsonPath('data.provider_reference', null)
            ->assertJsonPath('data.has_proof', true);

        $payment = PropertyPayment::query()->findOrFail($paymentId);
        Storage::disk('local')->assertExists($payment->proof_path);
        Storage::disk('public')->assertMissing($payment->proof_path);
        $this->getJson($receivablePath)
            ->assertOk()
            ->assertJsonPath('data.receivable.amount_paid', 0)
            ->assertJsonPath('data.receivable.remaining_amount', 900_000)
            ->assertJsonCount(1, 'data.payments')
            ->assertJsonPath('data.payments.0.id', $paymentId)
            ->assertJsonPath('data.payments.0.status', 'proof_submitted');
        $this->get($proofPath)->assertOk();
        $this->withHeaders($buyerHeaders)->get($proofPath)->assertForbidden();
    }

    public function test_published_sai_attestation_uses_exact_snapshot_and_disappears_from_pending(): void
    {
        [$advertiser, $headers] = $this->user('financial-oath-owner@example.test', '+967772000042');
        $property = $this->property($advertiser, 100_000_000, 'Financial oath');
        $term = $this->term($property, 'seller');
        $property->forceFill(['current_sai_term_id'=>$term->id])->saveQuietly();

        $this->withHeaders($headers)->getJson('/api/finance/sai-attestations/pending')
            ->assertOk()->assertJsonFragment(['property_id'=>$property->id,'text'=>PropertyFinancialService::SAI_ATTESTATION_TEXT]);
        $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/sai-attestation", ['accepted'=>false])->assertStatus(422);
        $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/sai-attestation", ['accepted'=>true])->assertOk();
        $this->assertDatabaseHas('property_sai_attestations', [
            'property_id'=>$property->id,'sai_term_id'=>$term->id,'user_id'=>$advertiser->id,
            'text_snapshot'=>PropertyFinancialService::SAI_ATTESTATION_TEXT,
        ]);
        $this->withHeaders($headers)->getJson('/api/finance/sai-attestations/pending')->assertOk()->assertJsonMissing(['property_id'=>$property->id]);
    }

    public function test_payment_review_task_is_visible_claimed_and_reviewed_only_by_assigned_agent(): void
    {
        [$agreementId, $property, , $buyer, , ] = $this->acceptedSaleDeal('buyer');
        $termId=(int)DB::table('property_deal_financial_terms')->where('property_agreement_id',$agreementId)->value('id');
        $methodId=(int)DB::table('property_payment_methods')->value('id');
        $paymentId=(int)DB::table('property_payments')->insertGetId([
            'reference'=>'PAY-TEST-REVIEW','deal_financial_term_id'=>$termId,'property_id'=>$property->id,
            'payer_user_id'=>$buyer->id,'advertiser_user_id'=>$property->user_id,'payment_method_id'=>$methodId,
            'mode'=>'platform_sai_only','status'=>'proof_submitted','required_amount'=>900000,'currency'=>'YER',
            'submitted_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
        ]);
        app(SupportTaskService::class)->projectPayment($paymentId);

        $projected=SupportTask::query()->where('source_type','payment_review')->where('source_id',$paymentId)->firstOrFail();
        $this->assertSame('new',$projected->status);
        $this->assertNull($projected->assigned_to_user_id);
        $this->assertNotNull($projected->support_team_id);

        [$agent, $agentHeaders] = $this->user(
            'financial-support-agent@example.test',
            '+967772000043',
            ['support_agent'],
        );
        $agent=$agent->fresh();
        $this->assertTrue($agent->hasRole('support_agent'));
        $this->assertTrue($agent->hasPermission('payments.review'));
        $this->assertFalse($agent->hasPermission('support.manage'));

        $this->withHeaders($agentHeaders)->getJson("/api/admin/finance/payments/$paymentId")->assertForbidden();
        $inbox=$this->withHeaders($agentHeaders)->getJson('/api/admin/workspace/tasks?scope=inbox&type=payment_review')->assertOk();

        $this->assertDatabaseHas('support_team_members',[
            'user_id'=>$agent->id,
            'support_team_id'=>$projected->support_team_id,
            'member_role'=>'agent',
        ]);
        $this->assertSame(1,(int)$inbox->json('meta.total'));
        $taskId=(int)$inbox->json('data.0.id');
        $this->assertSame((int)$projected->id,$taskId);

        [$manager, $managerHeaders] = $this->user('financial-support-manager@example.test', '+967772000044', ['support_manager']);
        DB::table('support_teams')->where('id', $projected->support_team_id)->update(['manager_user_id' => $manager->id]);
        $this->withHeaders($managerHeaders)->putJson("/api/admin/workspace/tasks/$taskId/assign", ['user_id' => $agent->id])
            ->assertOk()->assertJsonPath('data.assignment_source', 'assigned')->assertJsonPath('data.claimed_at', null);
        $this->withHeaders($agentHeaders)->getJson("/api/admin/finance/payments/$paymentId")->assertForbidden();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/finance/payments/$paymentId/review", ['decision' => 'confirm'])
            ->assertForbidden();

        $this->withHeaders($agentHeaders)->postJson("/api/admin/workspace/tasks/$taskId/claim")->assertOk()->assertJsonPath('data.is_mine',true);
        $this->withHeaders($agentHeaders)->getJson("/api/admin/finance/payments/$paymentId")->assertOk()->assertJsonPath('data.status','under_review');
        $this->withHeaders($agentHeaders)->postJson("/api/admin/finance/payments/$paymentId/review",['decision'=>'correction','note'=>'صورة الإثبات غير واضحة'])->assertOk()->assertJsonPath('data.status','correction_required');
        $this->assertDatabaseHas('support_tasks',['id'=>$taskId,'source_type'=>'payment_review','status'=>'waiting_user','assigned_to_user_id'=>$agent->id]);

        $payment = PropertyPayment::query()->findOrFail($paymentId);
        $payment->forceFill(['status' => 'proof_submitted'])->save();
        $this->assertSame($taskId, app(FinancialSupportTaskService::class)->projectPayment($payment)->id);
        $this->assertDatabaseHas('support_tasks', ['id' => $taskId, 'status' => 'needs_followup', 'assigned_to_user_id' => $agent->id]);
    }

    public function test_payment_review_routes_to_the_property_governorate_even_for_legacy_unassigned_proofs(): void
    {
        [$agreementId, $property, , $buyer] = $this->acceptedSaleDeal('buyer');
        $property->forceFill(['address' => 'المحافظة: محافظة ذمار - المدينة: ذمار', 'geo_cell_id' => null])->saveQuietly();
        $provinceId = (int) DB::table('governorates')->where('code', 'DHAMAR')->value('id');
        $localTeamId = (int) DB::table('support_teams')->where('governorate_id', $provinceId)->value('id');
        $fallbackTeamId = (int) DB::table('support_teams')->where('is_fallback', true)->value('id');
        $payment = PropertyPayment::query()->create([
            'reference' => 'PAY-REGIONAL-REVIEW',
            'deal_financial_term_id' => DB::table('property_deal_financial_terms')->where('property_agreement_id', $agreementId)->value('id'),
            'property_id' => $property->id,
            'payer_user_id' => $buyer->id,
            'advertiser_user_id' => $property->user_id,
            'payment_method_id' => DB::table('property_payment_methods')->value('id'),
            'mode' => 'platform_sai_only', 'status' => 'proof_submitted', 'required_amount' => 900_000, 'currency' => 'YER',
            'submitted_at' => now(),
        ]);

        $service = app(FinancialSupportTaskService::class);
        $task = $service->projectPayment($payment);
        $this->assertSame($fallbackTeamId, (int) $task->support_team_id);
        $this->assertSame($provinceId, (int) $task->governorate_id);

        [$reviewer] = $this->user(
            'financial-regional-reviewer@example.test', '+967772000045', ['support_agent'],
        );
        DB::table('support_team_members')->insert([
            'support_team_id' => $localTeamId, 'user_id' => $reviewer->id,
            'member_role' => 'agent', 'is_available' => true, 'capacity' => 10,
            'joined_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        $task = $service->projectPayment($payment);
        $this->assertSame($localTeamId, (int) $task->support_team_id);
        $this->assertSame($provinceId, (int) $task->governorate_id);
        $task->forceFill(['support_team_id' => $fallbackTeamId, 'governorate_id' => null])->save();
        $service->refreshUnassignedRouting();
        $this->assertDatabaseHas('support_tasks', [
            'id' => $task->id, 'support_team_id' => $localTeamId, 'governorate_id' => $provinceId,
        ]);
    }

    public function test_batched_overdue_checks_preserve_visibility_and_financial_amounts(): void
    {
        [$agreementId,$property,$advertiser,$buyer,$advertiserHeaders,$buyerHeaders]=$this->acceptedSaleDeal('seller');
        $this->withHeaders($buyerHeaders)->postJson("/api/finance/agreements/$agreementId/direct-confirmation",['decision'=>'confirmed'])->assertOk();
        $this->withHeaders($advertiserHeaders)->postJson("/api/finance/agreements/$agreementId/direct-confirmation",['decision'=>'confirmed'])->assertOk();
        $receivable=DB::table('property_platform_receivables')->where('advertiser_user_id',$advertiser->id)->first();
        $this->assertNotNull($receivable);
        DB::table('property_platform_receivables')->where('id',$receivable->id)->update(['due_at'=>now()->subMinute()]);
        $ledgerCount=DB::table('property_financial_ledger_entries')->count();
        $service=app(PropertyFinancialService::class);
        $result=$service->overdueReceivablesFor([$advertiser->id,$buyer->id,$advertiser->id]);
        $this->assertTrue($result[$advertiser->id]);$this->assertFalse($result[$buyer->id]);
        $this->assertDatabaseHas('property_platform_receivables',['id'=>$receivable->id,'status'=>'open',
            'amount_total'=>$receivable->amount_total,'amount_paid'=>$receivable->amount_paid,'currency'=>$receivable->currency]);
        $this->assertNull($property->fresh()->financial_hold_at);
        $this->assertSame($ledgerCount,DB::table('property_financial_ledger_entries')->count());
        $count=DB::table('user_notifications')->where('user_id',$advertiser->id)->where('type','financial_hold_started')->count();
        $this->assertSame(0,$count);
        $service->overdueReceivablesFor([$advertiser->id,$buyer->id]);
        $this->assertSame($count,DB::table('user_notifications')->where('user_id',$advertiser->id)->where('type','financial_hold_started')->count());
        // Preserve disputed status and the exact paid/due predicates too.
        DB::table('property_platform_receivables')->where('id',$receivable->id)->update(['status'=>'disputed']);
        $this->assertTrue($service->overdueReceivablesFor([$advertiser->id])[$advertiser->id]);
        $this->assertDatabaseHas('property_platform_receivables',['id'=>$receivable->id,'status'=>'disputed']);
        DB::table('property_platform_receivables')->where('id',$receivable->id)->update(['amount_paid'=>$receivable->amount_total]);
        $this->assertFalse($service->overdueReceivablesFor([$advertiser->id])[$advertiser->id]);
        $this->assertSame([],$service->overdueReceivablesFor([]));
    }

    public function test_advertiser_and_manager_totals_keep_sale_currencies_separate(): void
    {
        [$yerId, , $advertiser, , $headers] = $this->acceptedSaleDeal('seller');
        [$usdId] = $this->acceptedSaleDeal('buyer', 'USD', [$advertiser, $headers]);
        foreach ([[$yerId, 'YER', 20000], [$usdId, 'USD', 12.50]] as [$id, $currency, $amount]) {
            $term = DB::table('property_deal_financial_terms')->where('property_agreement_id', $id)->first();
            $this->assertSame($currency, $term->currency);
            DB::table('property_payouts')->insert([
                'reference' => 'PAYOUT-'.$id, 'deal_financial_term_id' => $term->id,
                'advertiser_user_id' => $advertiser->id, 'amount' => $amount, 'currency' => $currency,
                'status' => 'pending', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }
        $this->withHeaders($headers)->getJson('/api/finance/account')->assertOk()
            ->assertJsonPath('data.summary.amounts_by_currency.pending_payouts.YER', 20000)
            ->assertJsonPath('data.summary.amounts_by_currency.pending_payouts.USD', 12.5)
            ->assertJsonPath('data.summary.pending_payouts', 20000);
        [, $managerHeaders] = $this->user('finance-manager@example.test', '+967770008856', ['super_admin']);
        $this->withHeaders($managerHeaders)->getJson('/api/admin/finance/summary')->assertOk()
            ->assertJsonPath('data.amounts_by_currency.pending_payouts_amount.USD', 12.5)
            ->assertJsonPath('data.pending_payouts_amount', 20000)
            ->assertJsonPath('data.amounts_by_currency.gross_transaction_value.USD', 90000000)
            ->assertJsonPath('data.gross_transaction_value', 90000000);
    }

    private function acceptedSaleDeal(string $payer, string $currency = 'YER', ?array $advertiserAccount = null): array
    {
        [$advertiser, $advertiserHeaders] = $advertiserAccount ?? $this->user('financial-deal-owner-'.$payer.'@example.test', '+96777200'.($payer === 'buyer' ? '0021' : '0031'));
        [$buyer, $buyerHeaders] = $this->user('financial-deal-buyer-'.$payer.'@example.test', '+96777200'.($payer === 'buyer' ? '0022' : '0032'));
        $property = $this->property($advertiser, 100_000_000, 'Financial deal '.$payer);
        $term = $this->term($property, $payer);
        $property->forceFill(['currency'=>$currency, 'current_sai_term_id'=>$term->id, 'price_display_mode'=>$payer === 'buyer' ? 'excludes_sai' : null])->save();

        $threadId = (int) $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()->json('data.id');

        $created = $this->withHeaders($buyerHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount'=>90_000_000,
                'currency'=>$currency,
            ])->assertCreated();
        $agreementId = (int) $created->json('data.id');
        $revisionId = (int) $created->json('data.current_revision.id');

        $this->withHeaders($buyerHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id'=>$revisionId])
            ->assertOk()->assertJsonPath('data.status', 'draft');
        $this->withHeaders($advertiserHeaders)
            ->postJson("/api/agreements/$agreementId/accept", ['revision_id'=>$revisionId])
            ->assertOk()->assertJsonPath('data.status', 'accepted');

        return [$agreementId, $property, $advertiser, $buyer, $advertiserHeaders, $buyerHeaders];
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name'=>'Financial V1 User',
            'email'=>$email,
            'phone'=>$phone,
            'phone_verified_at'=>now(),
            'profile_completed_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,
            'password'=>Hash::make('financial-v1-test-password'),
        ]);
        $roleIds = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $roleIds[$role->id] = ['assigned_by_user_id'=>null,'created_at'=>now()];
        }
        $user->roles()->sync($roleIds);
        $plain = 'finv1_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name'=>'financial-v1-test',
            'token_hash'=>hash('sha256', $plain),
            'token_prefix'=>substr($plain, 0, 12),
            'expires_at'=>now()->addHour(),
        ]);
        return [$user, ['Authorization'=>'Bearer '.$plain, 'Accept'=>'application/json']];
    }

    private function property(User $advertiser, float $price, string $title): Property
    {
        $asset = PropertyAsset::query()->create([
            'created_by_user_id'=>$advertiser->id,
            'identity_hash'=>hash('sha256', $title.uniqid('', true)),
            'identity_version'=>1,
            'property_type'=>'apartment',
            'canonical_address'=>'Financial V1 address',
            'canonical_latitude'=>15.3694,
            'canonical_longitude'=>44.1910,
            'area_m2'=>120,
            'bedrooms'=>3,
            'bathrooms'=>2,
            'status'=>'active',
        ]);
        return Property::query()->create([
            'user_id'=>$advertiser->id,
            'property_asset_id'=>$asset->id,
            'title'=>$title,
            'description'=>'Financial V1 acceptance fixture',
            'purpose'=>'sale',
            'type'=>'apartment',
            'price'=>$price,
            'currency'=>'YER',
            'area_m2'=>120,
            'bedrooms'=>3,
            'bathrooms'=>2,
            'address'=>'Financial V1 address',
            'latitude'=>15.3694,
            'longitude'=>44.1910,
            'status'=>'published',
            'review_status'=>'approved',
            'published_at'=>now(),
        ]);
    }

    private function term(Property $property, string $payer): PropertySaiTerm
    {
        return PropertySaiTerm::query()->create([
            'property_id'=>$property->id,
            'version'=>1,
            'advertiser_type'=>'owner',
            'purpose'=>'sale',
            'source_mode'=>'owner_fixed',
            'requested_broker_rate_percent'=>null,
            'sai_rate_percent'=>1,
            'payer'=>$payer,
            'calculation_basis'=>'final_sale_value',
            'platform_share_percent'=>100,
            'broker_share_percent'=>0,
            'platform_terms_status'=>'not_required',
            'platform_terms_accepted_at'=>null,
            'platform_terms_rejected_at'=>null,
            'created_by_user_id'=>$property->user_id,
        ]);
    }
}
