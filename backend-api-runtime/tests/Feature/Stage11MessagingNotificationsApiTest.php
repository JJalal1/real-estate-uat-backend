<?php
namespace Tests\Feature;

use App\Models\ConversationReport;
use App\Models\PrivateMessageAccessEvent;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Stage11MessagingNotificationsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_listing_conversation_is_private_and_new_message_creates_notification(): void
    {
        [$advertiser,$adHeaders]=$this->user('s11-ad@example.test','+967730000001');
        [, $buyerHeaders]=$this->user('s11-buyer@example.test','+967730000002');
        [, $outsiderHeaders]=$this->user('s11-outsider@example.test','+967730000003');
        $listing=$this->publishedListing($advertiser,'Stage 11 messaging listing');
        $this->withHeaders($adHeaders)->postJson("/api/properties/{$listing->id}/conversation")->assertUnprocessable();
        $created=$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$listing->id}/conversation")->assertCreated();
        $threadId=(int)$created->json('data.id');
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'Is this listing still available?'])->assertCreated();
        $this->withHeaders($outsiderHeaders)->getJson("/api/messages/threads/$threadId")->assertNotFound();
        $this->withHeaders($adHeaders)->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count',1);
        $this->withHeaders($adHeaders)->getJson("/api/messages/threads/$threadId")->assertOk()->assertJsonPath('data.messages.0.body','Is this listing still available?');
        $this->withHeaders($adHeaders)->getJson('/api/notifications/unread-count')->assertOk()->assertJsonPath('data.count',0);
    }

    public function test_private_content_admin_access_requires_report_permission_and_is_logged(): void
    {
        [$advertiser]=$this->user('s11-report-ad@example.test','+967730000004');
        [, $buyerHeaders]=$this->user('s11-report-buyer@example.test','+967730000005');
        [, $agentHeaders]=$this->user('s11-report-agent@example.test','+967730000006',['support_agent']);
        [, $managerHeaders]=$this->user('s11-report-manager@example.test','+967730000007',['support_manager']);
        $listing=$this->publishedListing($advertiser,'Stage 11 complaint listing');
        $threadId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$listing->id}/conversation")->json('data.id');
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'Private smoke-worthy message.'])->assertCreated();
        $report=$this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/report",['reason'=>'abuse','details'=>'I need support to review this conversation.'])->assertCreated();
        $reportId=(int)$report->json('data.id');
        $queue=$this->withHeaders($agentHeaders)->getJson('/api/admin/messages/reports')->assertOk();
        $this->assertArrayNotHasKey('messages',$queue->json('data.0'));
        $this->assertArrayNotHasKey('details',$queue->json('data.0'));
        $this->withHeaders($agentHeaders)->getJson("/api/admin/messages/reports/$reportId/content")->assertForbidden();
        $this->withHeaders($managerHeaders)->getJson("/api/admin/messages/reports/$reportId/content")->assertOk()->assertJsonPath('data.messages.0.body','Private smoke-worthy message.');
        $this->assertDatabaseHas('audit_logs',['action'=>'conversations.private_content_opened','subject_id'=>$reportId]);
        $this->assertDatabaseHas('private_message_access_events',['conversation_report_id'=>$reportId,'action'=>'opened_reported_private_content']);
        $this->withHeaders($managerHeaders)->patchJson("/api/admin/messages/reports/$reportId/resolve",['status'=>'resolved','resolution_note'=>'Reviewed under the authorized complaint workflow.'])->assertOk()->assertJsonPath('data.status','resolved');
    }

    public function test_private_access_history_is_immutable(): void
    {
        $event=PrivateMessageAccessEvent::query()->create(['conversation_report_id'=>999,'thread_id'=>999,'actor_user_id'=>null,'actor_name_snapshot'=>'Snapshot','action'=>'opened_reported_private_content','created_at'=>now()]);
        $updateFailed=false;try{DB::table('private_message_access_events')->where('id',$event->id)->update(['action'=>'tampered']);}catch(\Throwable){$updateFailed=true;}
        $deleteFailed=false;try{DB::table('private_message_access_events')->where('id',$event->id)->delete();}catch(\Throwable){$deleteFailed=true;}
        $this->assertTrue($updateFailed);$this->assertTrue($deleteFailed);
    }

    public function test_support_staff_reply_creates_in_app_notification(): void
    {
        [, $requesterHeaders]=$this->user('s11-support-requester@example.test','+967730000008');
        [, $agentHeaders]=$this->user('s11-support-agent@example.test','+967730000009',['support_agent']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',['subject'=>'Notification case','description'=>'Please send me a support reply notification.','category'=>'other'])->assertCreated()->json('data.id');
        $this->withHeaders($agentHeaders)->postJson("/api/admin/support/cases/$caseId/reply",['body'=>'Support notification test reply.'])->assertOk();
        $items=$this->withHeaders($requesterHeaders)->getJson('/api/notifications')->assertOk();
        $this->assertContains('support_reply',collect($items->json('data'))->pluck('type')->all());
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
