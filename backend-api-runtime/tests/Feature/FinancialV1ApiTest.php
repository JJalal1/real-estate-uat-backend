<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertySaiTerm;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class FinancialV1ApiTest extends TestCase
{
    use RefreshDatabase;

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

        $this->getJson("/api/properties/{$property->id}")
            ->assertOk()
            ->assertJsonPath('data.base_price', 100000000)
            ->assertJsonPath('data.display_price', 101000000)
            ->assertJsonPath('data.price_display_note', 'المبلغ شامل السعي')
            ->assertJsonPath('data.sai.amount', 1000000)
            ->assertJsonMissingPath('data.platform_share_amount')
            ->assertJsonMissingPath('data.advertiser_sai_share_amount');
    }

    public function test_direct_deal_creates_24_hour_receivable_blocks_new_listing_and_hides_after_deadline(): void
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
        $this->assertDatabaseHas('property_financial_holds', [
            'user_id'=>$advertiser->id,
            'reason'=>'platform_receivable_open',
            'source_id'=>$receivable->id,
        ]);
        $this->assertDatabaseHas('property_financial_ledger_entries', [
            'entry_type'=>'platform_receivable_created',
            'source_type'=>'property_platform_receivable',
            'source_id'=>$receivable->id,
        ]);

        // The financial hold blocks new listings immediately, before the 24h visibility deadline.
        $this->withHeaders($advertiserHeaders)
            ->postJson('/api/properties', [])
            ->assertStatus(409)
            ->assertJsonFragment(['message'=>'لديك مستحقات للمنصة. سدّد المستحقات الحالية قبل إنشاء أو إرسال إعلان جديد.']);

        // Before the deadline, the already-published listing remains discoverable.
        $this->getJson("/api/properties/{$property->id}")->assertOk();

        // Once the 24h deadline passes, the published listing disappears publicly
        // without deleting it; the advertiser still sees it in My Listings.
        DB::table('property_platform_receivables')->where('id', $receivable->id)->update([
            'due_at'=>now()->subMinute(),
            'updated_at'=>now(),
        ]);
        $this->getJson("/api/properties/{$property->id}")->assertNotFound();
        $this->getJson('/api/properties')
            ->assertOk()
            ->assertJsonMissing(['id'=>$property->id]);
        $this->withHeaders($advertiserHeaders)
            ->getJson('/api/properties/mine/list')
            ->assertOk()
            ->assertJsonFragment(['id'=>$property->id]);
        $this->assertDatabaseHas('properties', ['id'=>$property->id, 'status'=>'published']);
    }

    private function acceptedSaleDeal(string $payer): array
    {
        [$advertiser, $advertiserHeaders] = $this->user('financial-deal-owner-'.$payer.'@example.test', '+96777200'.($payer === 'buyer' ? '0021' : '0031'));
        [$buyer, $buyerHeaders] = $this->user('financial-deal-buyer-'.$payer.'@example.test', '+96777200'.($payer === 'buyer' ? '0022' : '0032'));
        $property = $this->property($advertiser, 100_000_000, 'Financial deal '.$payer);
        $term = $this->term($property, $payer);
        $property->forceFill(['current_sai_term_id'=>$term->id, 'price_display_mode'=>$payer === 'buyer' ? 'excludes_sai' : null])->save();

        $threadId = (int) $this->withHeaders($buyerHeaders)
            ->postJson("/api/properties/{$property->id}/conversation")
            ->assertCreated()->json('data.id');

        $created = $this->withHeaders($buyerHeaders)
            ->postJson("/api/messages/threads/$threadId/agreement", [
                'agreed_amount'=>90_000_000,
                'currency'=>'YER',
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

    private function user(string $email, string $phone): array
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
        $role = Role::query()->where('key', 'registered_user')->firstOrFail();
        $user->roles()->sync([$role->id=>['assigned_by_user_id'=>null,'created_at'=>now()]]);
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
