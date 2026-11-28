<?php
namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\ListingEditorDraft;
use App\Models\Property;
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
            'latitude'=>15.4,'longitude'=>44.2,'step'=>1,'fields'=>['title'=>'إعلان صناعي للاسترداد','monthly_rent'=>'100000','rental_term_months'=>'12','advance_months'=>'1','area'=>'90','bedrooms'=>'2','bathrooms'=>'1','floor_number'=>'1','description'=>'شقة في صنعاء','phone'=>'771111111']];
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
    public function test_sale_drafts_restore_amounts_in_the_selected_currency(): void
    {
        [, $headers] = $this->actor('sale-currency', 'broker');
        foreach (['USD', 'SAR', 'YER'] as $currency) {
            $url = '/api/listing-editor-drafts/'.Str::uuid();
            $payload = [
                'draft_kind'=>'saved', 'purpose'=>'sale', 'currency'=>$currency,
                'sai_amount_type'=>'fixed', 'fields'=>['price'=>'50000', 'fixed_sai_amount'=>'2000'],
            ];
            $this->withHeaders($headers)->putJson($url, ['payload'=>$payload, 'expected_revision'=>0])->assertOk();
            $this->withHeaders($headers)->getJson($url)->assertOk()
                ->assertJsonPath('data.payload.currency', $currency)
                ->assertJsonPath('data.payload.fields.price', '50000')
                ->assertJsonPath('data.payload.fields.fixed_sai_amount', '2000');
            if ($currency !== 'YER') {
                unset($payload['currency']);
                $this->withHeaders($headers)->putJson($url, ['payload'=>$payload, 'expected_revision'=>1])->assertConflict();
            }
        }
    }

    public function test_historical_currency_can_only_be_retained_on_the_linked_listing(): void
    {
        [$owner, $headers] = $this->actor('legacy-currency', 'broker');
        $listing = Property::create([
            'user_id'=>$owner->id, 'title'=>'Existing sale', 'purpose'=>'sale', 'type'=>'house',
            'currency'=>'EUR', 'price'=>75000, 'latitude'=>15.4, 'longitude'=>44.2, 'status'=>'draft', 'review_status'=>'draft',
        ]);
        $url = '/api/listing-editor-drafts/'.Str::uuid();
        $payload = ['draft_kind'=>'saved', 'purpose'=>'sale', 'currency'=>'EUR', 'fields'=>['price'=>'75000']];
        $this->withHeaders($headers)->putJson($url, ['expected_revision'=>0, 'payload'=>$payload])->assertUnprocessable();
        $this->withHeaders($headers)->putJson($url, ['property_id'=>$listing->id, 'expected_revision'=>0, 'payload'=>$payload])
            ->assertOk()->assertJsonPath('data.payload.currency', 'EUR');
        $payload['fields']['price'] = '78000';
        $this->withHeaders($headers)->putJson($url, ['expected_revision'=>1, 'payload'=>$payload])
            ->assertOk()->assertJsonPath('data.payload.currency', 'EUR')->assertJsonPath('data.payload.fields.price', '78000');
        $payload['currency'] = 'GBP';
        $this->withHeaders($headers)->putJson($url, ['expected_revision'=>2, 'payload'=>$payload])->assertUnprocessable();
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
    public function test_only_progress_above_half_replaces_automatic_work_and_restart_protects_manual_work(): void
    {
        [$actor, $headers] = $this->actor('marketplace-drafts', null);
        $base = '/api/listing-editor-drafts';
        $half = ['editor_version'=>11, 'draft_kind'=>'recovery', 'type'=>'land', 'purpose'=>'rent',
            'latitude'=>15.4, 'fields'=>['title'=>'أرض للإيجار']];
        $automatic = $base.'/'.Str::uuid();
        $this->withHeaders($headers)->putJson($automatic, ['payload'=>$half, 'expected_revision'=>0])->assertUnprocessable();
        $this->assertDatabaseCount('listing_editor_drafts', 0);
        $manual = $base.'/'.Str::uuid();
        $this->putJson($manual, ['payload'=>array_merge($half, ['draft_kind'=>'saved']), 'expected_revision'=>0])
            ->assertOk()->assertJsonPath('data.progress', 50);
        $payload = $half + ['longitude'=>44.2];
        $this->putJson($automatic, ['payload'=>$payload, 'expected_revision'=>0])->assertOk()->assertJsonPath('data.progress', 75);
        $next = $base.'/'.Str::uuid();
        $this->putJson($next, ['payload'=>$payload, 'expected_revision'=>0])->assertOk();
        $this->getJson($automatic)->assertGone();
        $this->getJson($base)->assertOk()->assertJsonCount(2, 'data');

        $reset = now()->utc();
        $this->postJson($base.'/restart', ['started_at'=>$reset->toISOString()])->assertOk();
        $this->getJson($next)->assertGone();
        $this->getJson($manual)->assertOk();
        $late = $base.'/'.Str::uuid();
        $this->putJson($late, ['payload'=>$payload, 'expected_revision'=>0, 'first_saved_at'=>$reset->copy()->subSecond()->toISOString()])->assertGone();
        $this->putJson($late, ['payload'=>$half, 'expected_revision'=>0])->assertUnprocessable();
        $this->getJson($base)->assertJsonCount(1, 'data');
        $this->putJson($late, ['payload'=>$payload, 'expected_revision'=>0])->assertOk();
        $this->postJson($base.'/restart', ['started_at'=>$reset->toISOString()])->assertOk();
        $this->getJson($late)->assertOk();
        $this->assertSame(1, ListingEditorDraft::where('user_id',$actor->id)->where('payload->draft_kind','recovery')->count());
    }

    public function test_seven_day_lifetime_uses_first_save_and_leaves_listed_property_intact(): void
    {
        [$user, $headers] = $this->actor('marketplace-expiry', null);
        $base = '/api/listing-editor-drafts';
        $key = (string)Str::uuid();
        $prior = now()->utc()->subDays(7)->addMinutes(5);
        $payload = $this->payload('saved');
        $this->withHeaders($headers)->putJson("$base/$key", ['payload'=>$payload, 'expected_revision'=>0, 'first_saved_at'=>$prior->toISOString()])
            ->assertOk()->assertJsonPath('data.first_saved_at', $prior->toISOString());
        $this->putJson("$base/$key", ['payload'=>$payload, 'expected_revision'=>1, 'first_saved_at'=>now()->toISOString()])
            ->assertOk()->assertJsonPath('data.first_saved_at', $prior->toISOString());
        $property = ['user_id'=>$user->id,'title'=>'مسودة اختبار','type'=>'land','purpose'=>'sale','price'=>1000,'latitude'=>15.4,'longitude'=>44.2];
        $expired = \App\Models\Property::create($property + ['status'=>'draft', 'review_status'=>'draft']);
        $expired->forceFill(['draft_expires_at'=>now()->addMinutes(5)])->save();
        $published = \App\Models\Property::create($property + ['status'=>'published', 'review_status'=>'approved']);
        $this->travel(6)->minutes();
        $this->getJson("$base/$key")->assertGone();
        $this->putJson("$base/$key", ['payload'=>$payload,'expected_revision'=>2])->assertGone();
        $this->getJson($base)->assertJsonCount(0,'data');
        $this->assertNull(\App\Models\Property::find($expired->id));
        $this->artisan('listings:expire-drafts')->assertSuccessful();
        $this->assertDatabaseMissing('properties', ['id'=>$expired->id]);
        $this->assertDatabaseHas('properties', ['id'=>$published->id, 'status'=>'published']);
        $retired = ListingEditorDraft::where('client_key', $key)->firstOrFail();
        $this->assertSame('retired', $retired->payload['draft_kind']);
        $this->assertSame([], $retired->payload['fields']);
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
