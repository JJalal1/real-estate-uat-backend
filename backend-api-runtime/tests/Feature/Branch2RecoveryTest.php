<?php
namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\ListingEditorDraft;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class Branch2RecoveryTest extends TestCase
{
    use RefreshDatabase;
    private function payload(string $kind='recovery'): array
    {
        return ['editor_version'=>10,'draft_kind'=>$kind,'entry_method'=>'assistant','type'=>'apartment','purpose'=>'rent',
            'step'=>1,'fields'=>['title'=>'إعلان صناعي للاسترداد','monthly_rent'=>'100000','phone'=>'771111111']];
    }
    public function test_recovery_retirement_clears_private_work_and_fences_late_writes(): void
    {
        [$user,$a]=$this->actor('b2-retire','broker');$key=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>0])->assertOk()
            ->assertJsonPath('data.payload.editor_version',10)->assertJsonPath('data.payload.draft_kind','recovery');
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertOk();
        $draft=ListingEditorDraft::where('user_id',$user->id)->where('client_key',$key)->firstOrFail();
        $this->assertSame('retired',$draft->payload['draft_kind']);$this->assertSame([],$draft->payload['fields']);$this->assertSame([],$draft->images);
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>1])->assertStatus(410);
        $this->withHeaders($a)->getJson($url)->assertStatus(410);
        $this->withHeaders($a)->getJson('/api/listing-editor-drafts')->assertJsonCount(0,'data')->assertJsonPath('meta.recovery_contract',1);
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertOk();
    }
    public function test_retire_before_the_first_delayed_save_prevents_recreation(): void
    {
        [, $a]=$this->actor('b2-late','broker');$key=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>0])->assertOk();
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>0])->assertStatus(410);
        $this->assertDatabaseCount('properties',0);
    }
    public function test_explicit_and_legacy_drafts_are_protected_and_only_explicit_delete_removes_them(): void
    {
        [, $a]=$this->actor('b2-saved','broker');
        foreach ([$this->payload('saved'),['editor_version'=>9,'fields'=>['title'=>'مسودة قديمة محفوظة']]] as $payload) {
            $url='/api/listing-editor-drafts/'.Str::uuid();
            $this->withHeaders($a)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
            $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertConflict();
            $this->withHeaders($a)->getJson($url)->assertOk()->assertJsonPath('data.payload.fields.title',$payload['fields']['title']);
            $this->withHeaders($a)->deleteJson($url)->assertOk();
        }
    }
    public function test_stale_revision_and_other_account_cannot_retire_recovery(): void
    {
        [, $a]=$this->actor('b2-owner','broker');[, $b]=$this->actor('b2-other','broker');$url='/api/listing-editor-drafts/'.Str::uuid();
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>0])->assertOk();
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>0])->assertConflict();
        $this->withHeaders($b)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertNotFound();
        $this->withHeaders($a)->getJson($url)->assertOk()->assertJsonPath('data.revision',1);
    }
    public function test_explicit_save_is_sticky_and_retries_keep_the_same_checkpoint(): void
    {
        [, $a]=$this->actor('b2-sticky','broker');$url='/api/listing-editor-drafts/'.Str::uuid();
        $payload=$this->payload('saved');$payload['checkpoint_key']=(string)Str::uuid();
        $this->withHeaders($a)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        $next=$payload;$next['draft_kind']='recovery';$next['checkpoint_key']=(string)Str::uuid();
        $this->withHeaders($a)->putJson($url,['payload'=>$next,'expected_revision'=>1])->assertOk()->assertJsonPath('data.payload.draft_kind','saved');
        $this->withHeaders($a)->putJson($url,['payload'=>$next,'expected_revision'=>1])->assertOk()->assertJsonPath('data.revision',2);
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>2])->assertConflict();
    }
    public function test_a_retired_recovery_does_not_consume_the_personal_listing_slot(): void
    {
        [, $a]=$this->actor('b2-personal','owner');$url='/api/listing-editor-drafts/'.Str::uuid();
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>0])->assertOk();
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertOk();
        $this->withHeaders($a)->putJson('/api/listing-editor-drafts/'.Str::uuid(),['payload'=>$this->payload(),'expected_revision'=>0])->assertOk();
    }
    public function test_cleanup_failure_is_visible_and_can_be_retried_without_reviving_the_draft(): void
    {
        [$user,$a]=$this->actor('b2-cleanup','broker');$key=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($a)->putJson($url,['payload'=>$this->payload(),'expected_revision'=>0])->assertOk();
        $draft=ListingEditorDraft::where('user_id',$user->id)->where('client_key',$key)->firstOrFail();
        $draft->images=[(string)Str::uuid()=>'editor-drafts/'.$user->id.'/synthetic.jpg'];$draft->save();
        $this->mock(\App\Services\ListingImageService::class,fn($mock)=>$mock->shouldReceive('removeIfUnused')->once()->andThrow(new \RuntimeException('Synthetic storage failure')));
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertStatus(500);
        $this->assertSame('retired',$draft->fresh()->payload['draft_kind']);
        $this->mock(\App\Services\ListingImageService::class,fn($mock)=>$mock->shouldReceive('removeIfUnused')->once()->andReturnNull());
        $this->withHeaders($a)->deleteJson($url,['recovery_only'=>true,'expected_revision'=>1])->assertOk();
        $this->assertArrayNotHasKey('cleanup_paths',$draft->fresh()->payload);
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
