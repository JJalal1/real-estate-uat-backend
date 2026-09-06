<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\PropertyRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UatPropertyRequestsPhase2ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_requester_crud_is_private_and_close_preserves_history(): void
    {
        [$owner,$headers]=$this->user('requester@example.test');[, $other]=$this->user('other@example.test');
        $created=$this->withHeaders($headers)->postJson('/api/property-requests',$this->payload())->assertCreated()->assertJsonPath('data.status','active');
        $id=$created->json('data.id');
        $this->withHeaders($other)->getJson("/api/property-requests/$id")->assertNotFound();
        $this->withHeaders($headers)->getJson('/api/property-requests')->assertOk()->assertJsonCount(1,'data');
        $this->withHeaders($headers)->patchJson("/api/property-requests/$id",array_merge($this->payload(),['budget_max'=>250000]))->assertOk()->assertJsonPath('data.budget_max',250000);
        $this->withHeaders($headers)->postJson("/api/property-requests/$id/close")->assertOk()->assertJsonPath('data.status','closed');
        $this->assertDatabaseHas('property_requests',['id'=>$id,'requester_user_id'=>$owner->id,'status'=>'closed']);
        $this->withHeaders($headers)->patchJson("/api/property-requests/$id",$this->payload())->assertStatus(409);
    }

    public function test_validation_rejects_invalid_ranges(): void
    {
        [, $headers]=$this->user('validation@example.test');
        $this->withHeaders($headers)->postJson('/api/property-requests',array_merge($this->payload(),['budget_min'=>20,'budget_max'=>10,'active_duration_days'=>181]))
            ->assertUnprocessable()->assertJsonValidationErrors(['budget_max','active_duration_days']);
    }

    public function test_only_verified_broker_or_office_can_research_and_suggest_eligible_owned_property(): void
    {
        [$requester,$requesterHeaders]=$this->user('buyer@example.test');
        [, $basicHeaders]=$this->user('basic@example.test');
        [$broker,$brokerHeaders]=$this->user('broker@example.test','broker');
        $requestId=$this->withHeaders($requesterHeaders)->postJson('/api/property-requests',$this->payload())->json('data.id');
        $property=$this->property($broker);
        $this->withHeaders($basicHeaders)->getJson('/api/researcher-requests')->assertForbidden();
        $this->withHeaders($brokerHeaders)->getJson('/api/researcher-requests')
            ->assertOk()->assertJsonPath('data.0.id',$requestId)
            ->assertJsonMissingPath('data.0.requester_user_id')
            ->assertJsonMissingPath('data.0.requester_phone');
        $response=$this->withHeaders($brokerHeaders)->postJson("/api/researcher-requests/$requestId/suggestions",['property_id'=>$property->id,'note'=>'مناسب للطلب'])->assertCreated();
        $response->assertJsonPath('data.property_id',$property->id);
        $this->assertDatabaseHas('property_requests',['id'=>$requestId,'status'=>'matched']);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$requester->id,'type'=>'property_suggestion','entity_type'=>'property_suggestion']);
        $this->withHeaders($brokerHeaders)->postJson("/api/researcher-requests/$requestId/suggestions",['property_id'=>$property->id])->assertStatus(409);
    }

    public function test_researcher_cannot_suggest_another_users_or_unpublished_property(): void
    {
        [, $requesterHeaders]=$this->user('buyer2@example.test');[$broker,$brokerHeaders]=$this->user('broker2@example.test','office');[$other]=$this->user('publisher@example.test');
        $requestId=$this->withHeaders($requesterHeaders)->postJson('/api/property-requests',$this->payload())->json('data.id');
        $foreign=$this->property($other);$draft=$this->property($broker,'draft','draft');
        $this->withHeaders($brokerHeaders)->postJson("/api/researcher-requests/$requestId/suggestions",['property_id'=>$foreign->id])->assertStatus(422);
        $this->withHeaders($brokerHeaders)->postJson("/api/researcher-requests/$requestId/suggestions",['property_id'=>$draft->id])->assertStatus(422);
    }

    public function test_elapsed_request_becomes_expired_and_is_not_researchable(): void
    {
        [$requester,$requesterHeaders]=$this->user('expired-buyer@example.test');
        [, $brokerHeaders]=$this->user('expired-broker@example.test','broker');
        $row=PropertyRequest::query()->create(array_merge($this->payload(),[
            'requester_user_id'=>$requester->id,'status'=>'active','expires_at'=>now()->subMinute(),
        ]));
        $this->withHeaders($requesterHeaders)->getJson('/api/property-requests')->assertOk()->assertJsonPath('data.0.status','expired');
        $this->withHeaders($brokerHeaders)->getJson('/api/researcher-requests')->assertOk()->assertJsonCount(0,'data');
        $this->assertDatabaseHas('property_requests',['id'=>$row->id,'status'=>'expired']);
        $this->assertNotNull($row->fresh()->expired_at);
    }

    private function payload(): array { return ['operation_type'=>'sale','property_type'=>'apartment','governorate'=>'صنعاء','district'=>'حدة','area'=>null,'budget_min'=>100000,'budget_max'=>200000,'currency'=>'YER','requested_area_min'=>80,'requested_area_max'=>150,'rooms'=>2,'additional_specifications'=>'قريب من الخدمات','active_duration_days'=>30]; }
    private function property(User $user,string $status='published',string $review='approved'): Property { return Property::query()->create(['user_id'=>$user->id,'title'=>'شقة مناسبة','description'=>'test','purpose'=>'sale','type'=>'apartment','price'=>150000,'currency'=>'YER','area_m2'=>100,'bedrooms'=>3,'bathrooms'=>2,'address'=>'حدة، صنعاء','latitude'=>15.3,'longitude'=>44.2,'status'=>$status,'review_status'=>$review]); }
    private function user(string $email,?string $type=null): array {
        $user=User::query()->create(['name'=>'Test User','email'=>$email,'phone'=>'+967'.substr(hash('crc32',$email),0,9),'phone_verified_at'=>now(),'profile_completed_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        if($type)AccountVerificationProfile::query()->create(['user_id'=>$user->id,'type'=>$type,'status'=>'approved','submitted_at'=>now()->subHour(),'reviewed_at'=>now()]);
        $plain='p2_'.substr(hash('sha512',$email),0,80);$user->apiTokens()->create(['name'=>'test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
