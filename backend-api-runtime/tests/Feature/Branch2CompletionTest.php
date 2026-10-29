<?php
namespace Tests\Feature;

use Illuminate\Support\Str;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use App\Models\User;
use App\Models\Role;
use App\Models\AccountVerificationProfile;
use Tests\TestCase;

/** Account persistence must retain review, confirmation and financial consent. */
class Branch2CompletionTest extends TestCase
{
    use RefreshDatabase;
    public function test_review_checkpoint_keeps_confirmed_facts_and_missing_only_state_without_submitting(): void
    {
        [, $headers]=$this->actor('b2-completion','broker');
        $key=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $payload=['editor_version'=>10,'draft_kind'=>'recovery','entry_method'=>'assistant','step'=>2,
            'type'=>'apartment','purpose'=>'rent','type_confirmed'=>true,'purpose_confirmed'=>true,
            'completion_only'=>false,'completion_reviewing'=>true,'sai_amount_type'=>'percentage',
            'sai_touched'=>true,'sai_terms_accepted'=>true,'parking'=>'no','facade'=>'north',
            'rental_conditions'=>[['kind'=>'advance','months'=>3]],
            'fields'=>['title'=>'شقة اختبار تكامل','monthly_rent'=>'100000','bedrooms'=>'4','bathrooms'=>'2',
                'floor_number'=>'2','governorate'=>'ذمار','broker_sai_rate_percent'=>'100','phone'=>'771234567']];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        $this->withHeaders($headers)->getJson($url)->assertOk()
            ->assertJsonPath('data.payload.completion_reviewing',true)->assertJsonPath('data.payload.completion_only',false)
            ->assertJsonPath('data.payload.type_confirmed',true)->assertJsonPath('data.payload.purpose_confirmed',true)
            ->assertJsonPath('data.payload.sai_terms_accepted',true)->assertJsonPath('data.payload.sai_touched',true)
            ->assertJsonPath('data.payload.fields.monthly_rent','100000')->assertJsonPath('data.payload.rental_conditions.0.months',3)
            ->assertJsonPath('data.payload.parking','no')->assertJsonPath('data.property_id',null);
        $this->assertDatabaseCount('properties',0);
        $payload['completion_reviewing']=false;$payload['completion_only']=true;
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>1])->assertOk()
            ->assertJsonPath('data.revision',2)->assertJsonPath('data.payload.completion_only',true);
        $this->assertDatabaseCount('listing_editor_drafts',1);
    }
    private function actor(string $name, ?string $type): array
    {
        $user = User::create(['name' => 'دلال اختباري', 'email' => $name.'@draft.example.test',
            'phone' => '+1202555'.substr(hash('sha256', $name), 0, 5), 'password' => Hash::make('fixture-pass'),
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'identity_policy_version' => 2, 'account_status' => 'active']);
        $user->roles()->sync([Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]]);
        if ($type) AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type,
            'status' => 'approved', 'submitted_at' => now(), 'reviewed_at' => now()]);
        $token = 'draft_fixture_'.$name;
        $user->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

}
