<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\SupportCase;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Wave2AccountSafetyTest extends TestCase
{
    use RefreshDatabase;

    public function test_block_is_bidirectional_for_new_messages_and_keeps_history_and_receipts(): void
    {
        [$ad,$a]=$this->user('w2ad@example.test','+967731100001');
        [$buyer,$b]=$this->user('w2buyer@example.test','+967731100002');
        $listing=$this->publishedListing($ad,'Blocking fixture');
        $id=$this->withHeaders($b)->postJson("/api/properties/$listing->id/conversation")->assertCreated()->json('data.id');
        $payload=['body'=>'Already delivered','client_message_id'=>'wave2-old-ack-001'];
        $receipt=$this->withHeaders($b)->postJson("/api/messages/threads/$id/messages",$payload)->assertCreated()->json('data.id');
        $this->withHeaders($a)->putJson("/api/users/$buyer->id/messaging-block")->assertOk();
        $this->withHeaders($a)->putJson("/api/users/$buyer->id/messaging-block")->assertOk();
        $this->assertDatabaseCount('user_messaging_blocks',1);
        $this->withHeaders($b)->postJson("/api/messages/threads/$id/messages",['body'=>'Bypass'])->assertForbidden();
        $this->withHeaders($a)->postJson("/api/messages/threads/$id/messages",['body'=>'Reverse bypass'])->assertForbidden();
        $this->withHeaders($b)->postJson("/api/messages/threads/$id/messages",$payload)->assertOk()->assertJsonPath('data.id',$receipt);
        $this->assertDatabaseCount('private_messages',1);
        $this->withHeaders($a)->getJson("/api/messages/threads/$id")->assertOk()->assertJsonPath('data.thread.blocked_by_me',true)->assertJsonPath('data.thread.can_send',false)->assertJsonCount(1,'data.messages');
        $this->withHeaders($b)->getJson("/api/messages/threads/$id")->assertOk()->assertJsonPath('data.thread.blocked_by_me',false)->assertJsonPath('data.thread.can_send',false);
        $this->withHeaders($b)->postJson("/api/properties/$listing->id/conversation")->assertForbidden();
        $this->withHeaders($b)->postJson("/api/messages/threads/$id/external-call")->assertForbidden();
        $this->withHeaders($b)->postJson("/api/messages/threads/$id/report",['reason'=>'abuse','details'=>'Please review existing history.'])->assertCreated();
        $this->assertDatabaseHas('audit_logs',['action'=>'messages.user_blocked','actor_user_id'=>$ad->id]);
    }

    public function test_unblock_only_changes_own_preference_and_other_block_still_applies(): void
    {
        [$a,$ha]=$this->user('w2a@example.test','+967731100003');
        [$b,$hb]=$this->user('w2b@example.test','+967731100004');
        $listing=$this->publishedListing($a,'Reciprocal fixture');
        $id=$this->withHeaders($hb)->postJson("/api/properties/$listing->id/conversation")->json('data.id');
        $this->withHeaders($ha)->putJson("/api/users/$b->id/messaging-block")->assertOk();
        $this->withHeaders($hb)->putJson("/api/users/$a->id/messaging-block")->assertOk();
        $this->withHeaders($ha)->deleteJson("/api/users/$b->id/messaging-block")->assertOk();
        $this->assertDatabaseCount('user_messaging_blocks',1);
        $this->withHeaders($ha)->postJson("/api/messages/threads/$id/messages",['body'=>'Still blocked'])->assertForbidden();
        $this->withHeaders($hb)->deleteJson("/api/users/$a->id/messaging-block")->assertOk();
        $this->withHeaders($ha)->postJson("/api/messages/threads/$id/messages",['body'=>'Available again'])->assertCreated();
    }

    public function test_block_list_is_account_scoped_minimal_and_self_block_is_rejected(): void
    {
        [$a,$ha]=$this->user('w2list-a@example.test','+967731100005');
        [$b,$hb]=$this->user('w2list-b@example.test','+967731100006');
        $this->withHeaders($ha)->putJson("/api/users/$a->id/messaging-block")->assertUnprocessable();
        $this->withHeaders($ha)->putJson("/api/users/$b->id/messaging-block")->assertOk();
        $row=$this->withHeaders($ha)->getJson('/api/account/blocked-users')->assertOk()->assertJsonCount(1,'data')->json('data.0');
        $this->assertSame($b->id,$row['id']);
        foreach (['email','phone','token_hash'] as $key) $this->assertArrayNotHasKey($key,$row);
        $this->withHeaders($hb)->getJson('/api/account/blocked-users')->assertOk()->assertJsonCount(0,'data');
        $this->withHeaders($hb)->deleteJson("/api/users/$a->id/messaging-block")->assertOk();
        $this->assertDatabaseCount('user_messaging_blocks',1);
    }

    public function test_deletion_request_requires_confirmation_is_idempotent_and_never_deletes(): void
    {
        [$user,$headers]=$this->user('w2delete@example.test','+967731100007');
        $listing=$this->publishedListing($user,'Retained listing');
        $before=$user->fresh()->getAttributes();
        $tokens=DB::table('api_tokens')->where('user_id',$user->id)->count();
        $this->withHeaders($headers)->postJson('/api/account/deletion-request')->assertUnprocessable();
        $one=$this->withHeaders($headers)->postJson('/api/account/deletion-request',['confirmed'=>true,'note'=>'Please review my request.'])->assertOk()->assertJsonPath('data.account_deleted',false)->assertJsonPath('data.final_deletion_enabled',false);
        $id=$one->json('data.case_id');
        $this->assertNotEmpty($one->json('data.reference'));
        $this->withHeaders($headers)->postJson('/api/account/deletion-request',['confirmed'=>true])->assertOk()->assertJsonPath('data.case_id',$id);
        $this->assertSame($before,$user->fresh()->getAttributes());
        $this->assertSame($tokens,DB::table('api_tokens')->where('user_id',$user->id)->count());
        $this->assertSame('published',$listing->fresh()->status);
        $this->assertDatabaseCount('support_cases',1);
        $this->assertDatabaseHas('support_tasks',['source_type'=>'support_ticket','source_id'=>$id]);
        $this->withHeaders($headers)->getJson('/api/account/deletion-request')->assertOk()->assertJsonPath('data.case_id',$id);
        [, $other]=$this->user('w2delete-other@example.test','+967731100008');
        $this->withHeaders($other)->getJson('/api/account/deletion-request')->assertOk()->assertJsonPath('data.status','not_requested')->assertJsonPath('data.reference',null);
        $this->withHeaders($other)->getJson("/api/support/cases/$id")->assertNotFound();
    }

    public function test_repeated_listing_report_returns_original_receipt_without_exposing_reporter_or_hiding_listing(): void
    {
        [$ad,$ha]=$this->user('w2report-ad@example.test','+967731100009');
        [, $reporter]=$this->user('w2reporter@example.test','+967731100010');
        $listing=$this->publishedListing($ad,'Reported fixture');
        $payload=['target_type'=>'listing','target_id'=>$listing->id,'reason'=>'misleading','details'=>'Please review these public details.'];
        $one=$this->withHeaders($reporter)->postJson('/api/reports',$payload)->assertCreated();
        $id=$one->json('data.id');
        $this->withHeaders($reporter)->postJson('/api/reports',$payload)->assertStatus(409)->assertJsonPath('code','report_already_received')->assertJsonPath('data.id',$id)->assertJsonPath('data.reference',$one->json('data.reference'));
        $this->assertDatabaseCount('support_cases',1);
        $this->withHeaders($ha)->getJson("/api/support/cases/$id")->assertNotFound();
        $this->assertSame('published',$listing->fresh()->status);
        $public=$this->getJson("/api/properties/$listing->id")->assertOk()->json('data');
        $this->assertArrayNotHasKey('reports',$public);
        $this->assertArrayNotHasKey('requester',$public);
    }

    public function test_account_safety_requires_auth_and_limits_requests(): void
    {
        $this->getJson('/api/account/blocked-users')->assertUnauthorized();
        $this->postJson('/api/account/deletion-request',['confirmed'=>true])->assertUnauthorized();
        [$a,$ha]=$this->user('w2limit-a@example.test','+967731100011');
        [$b]=$this->user('w2limit-b@example.test','+967731100012');
        for($i=0;$i<30;$i++) $this->withHeaders($ha)->putJson("/api/users/$b->id/messaging-block")->assertOk();
        $this->withHeaders($ha)->putJson("/api/users/$b->id/messaging-block")->assertStatus(429);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Stage 11 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        $sync=[];foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($sync);
        $plain='re11_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'stage11-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function publishedListing(User $advertiser,string $title): Property
    {
        $asset=PropertyAsset::query()->create(['created_by_user_id'=>$advertiser->id,'identity_hash'=>hash('sha256',$advertiser->email.'|'.$title),'identity_version'=>1,'property_type'=>'house','canonical_address'=>'Stage 11 Address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,'area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,'status'=>'active']);
        return Property::query()->create(['user_id'=>$advertiser->id,'property_asset_id'=>$asset->id,'owner_key'=>null,'title'=>$title,'description'=>'Stage 11 published listing','purpose'=>'sale','type'=>'house','price'=>55000000,'currency'=>'YER','area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,'address'=>'Stage 11 Address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now(),'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000']);
    }
}
