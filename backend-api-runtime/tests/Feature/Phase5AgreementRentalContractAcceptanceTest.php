<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase5AgreementRentalContractAcceptanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_agreement_is_property_conversation_bound_idempotent_and_private(): void
    {
        [$owner,$ownerHeaders]=$this->user('p5-owner1@example.test','+967770000001');
        [, $buyerHeaders]=$this->user('p5-buyer1@example.test','+967770000002');
        [, $outsiderHeaders]=$this->user('p5-outsider1@example.test','+967770000003');
        $property=$this->property($owner,'sale','Phase 5 sale agreement');
        $threadId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertCreated()->json('data.id');

        $first=$this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/agreement",[
            'agreed_amount'=>9500000,
            'currency'=>'yer',
            'conditions'=>'التسليم بعد الاتفاق النهائي بين الطرفين.',
        ])->assertCreated()->assertJsonPath('data.transaction_type','sale')->assertJsonPath('data.status','draft')->assertJsonPath('data.current_revision.currency','YER');
        $agreementId=(int)$first->json('data.id');
        $revisionId=(int)$first->json('data.current_revision.id');

        $this->withHeaders($ownerHeaders)->postJson("/api/messages/threads/$threadId/agreement",[
            'agreed_amount'=>123,
            'currency'=>'USD',
        ])->assertOk()->assertJsonPath('data.id',$agreementId)->assertJsonPath('data.current_revision.id',$revisionId);
        $this->assertDatabaseCount('property_agreements',1);
        $this->assertDatabaseCount('property_agreement_revisions',1);

        $this->withHeaders($outsiderHeaders)->getJson("/api/agreements/$agreementId")->assertNotFound();
        $this->withHeaders($outsiderHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revisionId])->assertNotFound();
        $this->withHeaders($ownerHeaders)->getJson("/api/agreements/$agreementId")->assertOk()->assertJsonPath('data.current_revision.agreed_amount',9500000);

        $public=$this->getJson("/api/properties/{$property->id}")->assertOk()->json('data');
        $this->assertArrayNotHasKey('agreement',$public);
        $this->assertArrayNotHasKey('rental_contract',$public);
    }

    public function test_new_revision_invalidates_old_acceptance_and_both_parties_must_accept_same_revision(): void
    {
        [$owner,$ownerHeaders]=$this->user('p5-owner2@example.test','+967770000004');
        [, $buyerHeaders]=$this->user('p5-buyer2@example.test','+967770000005');
        $property=$this->property($owner,'sale','Phase 5 revisions');
        $threadId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertCreated()->json('data.id');
        $created=$this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/agreement",['agreed_amount'=>10000000,'currency'=>'YER'])->assertCreated();
        $agreementId=(int)$created->json('data.id');$revision1=(int)$created->json('data.current_revision.id');

        $this->withHeaders($buyerHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revision1])->assertOk()->assertJsonPath('data.status','draft')->assertJsonPath('data.requester_accepted',true);
        $revised=$this->withHeaders($ownerHeaders)->postJson("/api/agreements/$agreementId/revisions",['agreed_amount'=>9750000])->assertOk()->assertJsonPath('data.requester_accepted',false)->assertJsonPath('data.advertiser_accepted',false);
        $revision2=(int)$revised->json('data.current_revision.id');$this->assertNotSame($revision1,$revision2);

        $this->withHeaders($buyerHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revision1])->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revision2])->assertOk()->assertJsonPath('data.status','draft');
        $final=$this->withHeaders($buyerHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revision2])->assertOk()->assertJsonPath('data.status','accepted')->assertJsonPath('data.requester_accepted',true)->assertJsonPath('data.advertiser_accepted',true);
        $this->assertNotNull($final->json('data.accepted_at'));
        $this->assertDatabaseHas('property_agreement_acceptances',['property_agreement_revision_id'=>$revision1]);
        $this->assertDatabaseHas('property_agreements',['id'=>$agreementId,'status'=>'accepted']);
        $this->withHeaders($ownerHeaders)->postJson("/api/agreements/$agreementId/revisions",['agreed_amount'=>9000000])->assertConflict();
        $this->withHeaders($buyerHeaders)->postJson("/api/agreements/$agreementId/cancel",['reason'=>'بعد القبول'])->assertConflict();
    }

    public function test_rental_contract_requires_accepted_rental_agreement_and_becomes_active_only_after_same_revision_acceptance(): void
    {
        [$owner,$ownerHeaders]=$this->user('p5-owner3@example.test','+967770000006');
        [, $tenantHeaders]=$this->user('p5-tenant3@example.test','+967770000007');
        [, $outsiderHeaders]=$this->user('p5-outsider3@example.test','+967770000008');
        $rent=$this->property($owner,'rent','Phase 5 rental');
        [$agreementId,$agreementRevision]=$this->acceptedAgreement($rent,$tenantHeaders,$ownerHeaders,[
            'agreed_amount'=>150000,'currency'=>'YER','rent_cadence'=>'monthly','security_deposit_amount'=>150000,
            'rental_start_date'=>now()->addMonth()->toDateString(),'rental_end_date'=>now()->addMonths(13)->toDateString(),'conditions'=>'اتفاق إيجار مبدئي داخل التطبيق.',
        ]);

        $contract=$this->withHeaders($tenantHeaders)->postJson("/api/agreements/$agreementId/rental-contract",[
            'payment_due_day'=>5,
            'additional_terms'=>'توثيق داخل التطبيق فقط ولا يدعي التسجيل الرسمي.',
        ])->assertCreated()->assertJsonPath('data.status','draft')->assertJsonPath('data.in_app_only',true)->assertJsonPath('data.official_registration',false)->assertJsonPath('data.current_revision.rent_amount',150000);
        $contractId=(int)$contract->json('data.id');$contractRevision=(int)$contract->json('data.current_revision.id');
        $this->withHeaders($outsiderHeaders)->getJson("/api/rental-contracts/$contractId")->assertNotFound();

        $this->withHeaders($tenantHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$contractRevision])->assertOk()->assertJsonPath('data.status','draft')->assertJsonPath('data.tenant_accepted',true);
        $this->withHeaders($ownerHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$contractRevision])->assertOk()->assertJsonPath('data.status','active')->assertJsonPath('data.advertiser_accepted',true);
        $this->assertDatabaseHas('rental_contracts',['id'=>$contractId,'status'=>'active']);

        $sale=$this->property($owner,'sale','Phase 5 sale no contract');
        [$saleAgreement,]=$this->acceptedAgreement($sale,$tenantHeaders,$ownerHeaders,['agreed_amount'=>20000000,'currency'=>'YER']);
        $this->withHeaders($tenantHeaders)->postJson("/api/agreements/$saleAgreement/rental-contract",[
            'start_date'=>now()->addMonth()->toDateString(),'end_date'=>now()->addYear()->toDateString(),
        ])->assertConflict();
        $this->assertDatabaseHas('property_agreements',['id'=>$agreementId,'status'=>'accepted']);
        $this->assertDatabaseHas('property_agreement_acceptances',['property_agreement_revision_id'=>$agreementRevision]);
    }

    public function test_contract_revision_requires_fresh_acceptance_and_termination_is_history_not_official_claim(): void
    {
        [$owner,$ownerHeaders]=$this->user('p5-owner4@example.test','+967770000009');
        [, $tenantHeaders]=$this->user('p5-tenant4@example.test','+967770000010');
        $rent=$this->property($owner,'rent','Phase 5 contract revisions');
        [$agreementId,]=$this->acceptedAgreement($rent,$tenantHeaders,$ownerHeaders,[
            'agreed_amount'=>100000,'currency'=>'YER','rent_cadence'=>'monthly','rental_start_date'=>now()->addMonth()->toDateString(),'rental_end_date'=>now()->addMonths(7)->toDateString(),
        ]);
        $created=$this->withHeaders($ownerHeaders)->postJson("/api/agreements/$agreementId/rental-contract",['payment_due_day'=>1])->assertCreated();$contractId=(int)$created->json('data.id');$revision1=(int)$created->json('data.current_revision.id');
        $this->withHeaders($tenantHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$revision1])->assertOk()->assertJsonPath('data.tenant_accepted',true);

        $revised=$this->withHeaders($ownerHeaders)->postJson("/api/rental-contracts/$contractId/revisions",['payment_due_day'=>10])->assertOk()->assertJsonPath('data.tenant_accepted',false)->assertJsonPath('data.advertiser_accepted',false);
        $revision2=(int)$revised->json('data.current_revision.id');
        $this->withHeaders($tenantHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$revision1])->assertConflict();
        $this->withHeaders($tenantHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$revision2])->assertOk();
        $this->withHeaders($ownerHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$revision2])->assertOk()->assertJsonPath('data.status','active');

        $terminated=$this->withHeaders($tenantHeaders)->postJson("/api/rental-contracts/$contractId/terminate",['reason'=>'تسجيل انتهاء العلاقة داخل المنصة'])->assertOk()->assertJsonPath('data.status','terminated')->assertJsonPath('data.official_registration',false);
        $this->assertNotNull($terminated->json('data.terminated_at'));
        $this->assertDatabaseHas('audit_logs',['action'=>'rental_contract.terminated','subject_type'=>'RentalContract','subject_id'=>$contractId]);
        $this->withHeaders($ownerHeaders)->postJson("/api/rental-contracts/$contractId/revisions",['payment_due_day'=>15])->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/rental-contracts/$contractId/accept",['revision_id'=>$revision2])->assertConflict();
    }

    private function acceptedAgreement(Property $property,array $requesterHeaders,array $ownerHeaders,array $terms): array
    {
        $threadId=(int)$this->withHeaders($requesterHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertCreated()->json('data.id');
        $created=$this->withHeaders($requesterHeaders)->postJson("/api/messages/threads/$threadId/agreement",$terms)->assertCreated();
        $agreementId=(int)$created->json('data.id');$revisionId=(int)$created->json('data.current_revision.id');
        $this->withHeaders($requesterHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revisionId])->assertOk();
        $this->withHeaders($ownerHeaders)->postJson("/api/agreements/$agreementId/accept",['revision_id'=>$revisionId])->assertOk()->assertJsonPath('data.status','accepted');
        return [$agreementId,$revisionId];
    }

    private function user(string $email,string $phone): array
    {
        $user=User::query()->create(['name'=>'Phase 5 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make(uniqid('phase5-fixture-',true))]);
        $role=Role::query()->where('key','registered_user')->firstOrFail();$user->roles()->sync([$role->id=>['assigned_by_user_id'=>null,'created_at'=>now()]]);
        $plain='p5_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'phase5-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function property(User $owner,string $purpose,string $title): Property
    {
        $asset=PropertyAsset::query()->create(['created_by_user_id'=>$owner->id,'identity_hash'=>hash('sha256',$title.uniqid('',true)),'identity_version'=>1,'property_type'=>'apartment','canonical_address'=>'Phase 5 address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,'area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'status'=>'active']);
        return Property::query()->create(['user_id'=>$owner->id,'property_asset_id'=>$asset->id,'title'=>$title,'description'=>'Phase 5 published listing','purpose'=>$purpose,'type'=>'apartment','price'=>$purpose==='rent'?150000:10000000,'currency'=>'YER','area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'address'=>'Phase 5 address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now()]);
    }
}
