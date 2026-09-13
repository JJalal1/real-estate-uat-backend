<?php
namespace Tests\Feature;

use App\Models\AdvertiserRating;
use App\Models\ListingComment;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\SupportCase;
use App\Models\User;
use App\Services\SupportCaseService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Stage10CommunitySupportApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_comments_require_published_listing_and_owner_controls_edits(): void
    {
        [$advertiser,$advertiserHeaders]=$this->user('s10-ad@example.test','+967720000001');
        [, $authorHeaders]=$this->user('s10-comment@example.test','+967720000002');
        [, $otherHeaders]=$this->user('s10-other@example.test','+967720000003');
        $listing=$this->publishedListing($advertiser,'Comment listing');

        $this->getJson("/api/properties/{$listing->id}/comments")->assertOk()->assertJsonCount(0,'data');
        $created=$this->withHeaders($authorHeaders)->postJson("/api/properties/{$listing->id}/comments",['body'=>'A useful public comment.']);
        $created->assertCreated()->assertJsonPath('data.status','visible')->assertJsonPath('data.is_owner',true);
        $commentId=(int)$created->json('data.id');
        $this->getJson("/api/properties/{$listing->id}/comments")->assertJsonCount(1,'data');
        $this->withHeaders($otherHeaders)->patchJson("/api/comments/$commentId",['body'=>'Not allowed'])->assertForbidden();
        $this->withHeaders($authorHeaders)->patchJson("/api/comments/$commentId",['body'=>'Edited useful comment.'])->assertOk()->assertJsonPath('data.body','Edited useful comment.');
        $this->withHeaders($authorHeaders)->deleteJson("/api/comments/$commentId")->assertOk();
        $this->getJson("/api/properties/{$listing->id}/comments")->assertJsonCount(0,'data');

        $draft=Property::query()->create(array_merge($listing->only(['user_id','property_asset_id','title','purpose','type','price','currency','latitude','longitude']),['title'=>'Draft','status'=>'draft','review_status'=>'draft']));
        $this->withHeaders($advertiserHeaders)->postJson("/api/properties/{$draft->id}/comments",['body'=>'No comment'])->assertNotFound();
    }

    public function test_content_moderator_can_hide_and_restore_comment_with_audit(): void
    {
        [$advertiser]=$this->user('s10-mod-ad@example.test','+967720000004');
        [, $authorHeaders]=$this->user('s10-mod-author@example.test','+967720000005');
        [, $moderatorHeaders]=$this->user('s10-content-mod@example.test','+967720000006',['content_moderator']);
        $listing=$this->publishedListing($advertiser,'Moderated listing');
        $commentId=(int)$this->withHeaders($authorHeaders)->postJson("/api/properties/{$listing->id}/comments",['body'=>'Potentially abusive comment.'])->json('data.id');
        $this->withHeaders($moderatorHeaders)->postJson("/api/admin/community/comments/$commentId/hide",['reason'=>'Confirmed abusive wording.'])->assertOk();
        $this->getJson("/api/properties/{$listing->id}/comments")->assertJsonCount(0,'data');
        $this->assertDatabaseHas('audit_logs',['action'=>'community.comment_hidden','subject_id'=>$commentId]);
        $this->withHeaders($moderatorHeaders)->postJson("/api/admin/community/comments/$commentId/unhide")->assertOk();
        $this->getJson("/api/properties/{$listing->id}/comments")->assertJsonCount(1,'data');
    }

    public function test_advertiser_rating_is_one_per_rater_and_excludes_hidden_ratings(): void
    {
        [$advertiser,$advertiserHeaders]=$this->user('s10-rate-ad@example.test','+967720000007');
        [, $raterA]=$this->user('s10-rater-a@example.test','+967720000008');
        [, $raterB]=$this->user('s10-rater-b@example.test','+967720000009');
        [, $moderator]=$this->user('s10-rate-mod@example.test','+967720000010',['content_moderator']);
        $listing=$this->publishedListing($advertiser,'Rating listing');

        $this->withHeaders($advertiserHeaders)->putJson("/api/advertisers/{$advertiser->id}/rating",['rating'=>5,'property_id'=>$listing->id])->assertUnprocessable();
        $this->withHeaders($raterA)->putJson("/api/advertisers/{$advertiser->id}/rating",['rating'=>5,'comment'=>'Excellent response.','property_id'=>$listing->id])->assertCreated();
        $this->withHeaders($raterA)->putJson("/api/advertisers/{$advertiser->id}/rating",['rating'=>3,'comment'=>'Updated view.','property_id'=>$listing->id])->assertOk();
        $this->withHeaders($raterB)->putJson("/api/advertisers/{$advertiser->id}/rating",['rating'=>5,'property_id'=>$listing->id])->assertCreated();
        $this->getJson("/api/advertisers/{$advertiser->id}/ratings/summary")->assertJsonPath('data.count',2)->assertJsonPath('data.average',4);
        $ratingId=(int)AdvertiserRating::query()->where('advertiser_user_id',$advertiser->id)->where('rating',3)->value('id');
        $this->withHeaders($moderator)->postJson("/api/admin/community/ratings/$ratingId/hide",['reason'=>'Rating violated content rules.'])->assertOk();
        $this->getJson("/api/advertisers/{$advertiser->id}/ratings/summary")->assertJsonPath('data.count',1)->assertJsonPath('data.average',5);
    }

    public function test_report_and_support_case_keep_private_content_out_of_queue_and_requester_thread(): void
    {
        [$advertiser]=$this->user('s10-report-ad@example.test','+967720000011');
        [$reporter,$reporterHeaders]=$this->user('s10-reporter@example.test','+967720000012');
        [, $agentHeaders]=$this->user('s10-agent@example.test','+967720000013',['support_agent']);
        [, $outsiderHeaders]=$this->user('s10-outsider@example.test','+967720000014');
        $listing=$this->publishedListing($advertiser,'Reported listing');

        $created=$this->withHeaders($reporterHeaders)->postJson('/api/reports',[
            'target_type'=>'listing','target_id'=>$listing->id,'reason'=>'misleading','details'=>'The public details appear inconsistent with the photos.',
        ]);
        $created->assertCreated()->assertJsonPath('data.kind','report')->assertJsonPath('data.status','open');
        $caseId=(int)$created->json('data.id');
        $case=SupportCase::query()->findOrFail($caseId);
        $this->assertTrue($case->sla_due_at->between(now()->addHours(47),now()->addHours(49)));
        $this->withHeaders($reporterHeaders)->postJson('/api/reports',[
            'target_type'=>'listing','target_id'=>$listing->id,'reason'=>'misleading','details'=>'Duplicate report should be rejected.',
        ])->assertStatus(409);
        $this->withHeaders($outsiderHeaders)->getJson("/api/support/cases/$caseId")->assertNotFound();
        $ticket=$this->withHeaders($reporterHeaders)->postJson('/api/support/cases',[
            'subject'=>'Private account recovery subject','description'=>'Private ticket body that must not appear in the support queue.','category'=>'account',
        ])->assertCreated();
        $ticketId=(int)$ticket->json('data.id');

        $queue=$this->withHeaders($agentHeaders)->getJson('/api/admin/support/cases')->assertOk();
        $rows=collect($queue->json('data'));
        $reportRow=$rows->firstWhere('id',$caseId);
        $ticketRow=$rows->firstWhere('id',$ticketId);
        $this->assertNotNull($reportRow);$this->assertNotNull($ticketRow);
        $this->assertArrayNotHasKey('description',$reportRow);
        $this->assertArrayNotHasKey('description',$ticketRow);
        $this->assertSame('Support ticket',$ticketRow['subject']);
        $this->assertNotSame('Private account recovery subject',$ticketRow['subject']);
        $this->claimSupportTask($agentHeaders, 'report', $caseId);
        $this->withHeaders($agentHeaders)->getJson("/api/admin/support/cases/$caseId")->assertOk()->assertJsonPath('data.description','The public details appear inconsistent with the photos.');
        $this->assertDatabaseHas('audit_logs',['action'=>'support.private_case_opened','subject_id'=>$caseId]);
        $this->withHeaders($agentHeaders)->postJson("/api/admin/support/cases/$caseId/note",['body'=>'Internal triage note.'])->assertOk();
        $this->withHeaders($agentHeaders)->postJson("/api/admin/support/cases/$caseId/reply",['body'=>'We are reviewing your report.'])->assertOk();
        $mine=$this->withHeaders($reporterHeaders)->getJson("/api/support/cases/$caseId")->assertOk();
        $bodies=collect($mine->json('data.messages'))->pluck('body')->all();
        $this->assertContains('We are reviewing your report.',$bodies);
        $this->assertNotContains('Internal triage note.',$bodies);
        $this->assertSame($reporter->id,(int)$mine->json('data.requester.id'));
    }

    public function test_48_hour_sla_escalates_open_cases_but_pauses_while_waiting_for_requester(): void
    {
        [, $requesterHeaders]=$this->user('s10-sla-requester@example.test','+967720000015');
        [, $agentHeaders]=$this->user('s10-sla-agent@example.test','+967720000016',['support_agent']);
        [, $managerHeaders]=$this->user('s10-sla-manager@example.test','+967720000017',['support_manager']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',[
            'subject'=>'SLA case','description'=>'This case will be made overdue for the automated test.','category'=>'technical',
        ])->assertCreated()->json('data.id');
        SupportCase::query()->whereKey($caseId)->update(['sla_due_at'=>now()->subMinute()]);
        $this->withHeaders($managerHeaders)->postJson('/api/admin/support/escalate-overdue')->assertOk()->assertJsonPath('data.escalated_count',1);
        $this->assertDatabaseHas('support_cases',['id'=>$caseId,'escalation_level'=>1,'priority'=>'high']);
        $this->assertDatabaseHas('support_case_events',['support_case_id'=>$caseId,'event'=>'sla_escalated']);
        $this->assertDatabaseHas('audit_logs',['action'=>'support.sla_escalated','subject_id'=>$caseId]);

        $waitingId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',[
            'subject'=>'Waiting case','description'=>'Support will ask the requester for more information.','category'=>'other',
        ])->assertCreated()->json('data.id');
        $this->claimSupportTask($agentHeaders, 'support_ticket', $waitingId);
        $this->withHeaders($agentHeaders)->patchJson("/api/admin/support/cases/$waitingId/status",['status'=>'waiting_requester'])->assertOk();
        SupportCase::query()->whereKey($waitingId)->update(['sla_due_at'=>now()->subMinute()]);
        $this->withHeaders($managerHeaders)->postJson('/api/admin/support/escalate-overdue')->assertOk()->assertJsonPath('data.escalated_count',0);
        $this->assertNull(SupportCase::query()->findOrFail($waitingId)->escalated_at);
    }

    public function test_support_history_is_immutable_and_actor_snapshot_survives_account_deletion(): void
    {
        [, $requesterHeaders]=$this->user('s10-history-requester@example.test','+967720000018');
        [$agent,$agentHeaders]=$this->user('s10-history-agent@example.test','+967720000019',['support_agent']);
        $caseId=(int)$this->withHeaders($requesterHeaders)->postJson('/api/support/cases',[
            'subject'=>'History case','description'=>'Immutable support history test case.','category'=>'other',
        ])->assertCreated()->json('data.id');
        $this->claimSupportTask($agentHeaders, 'support_ticket', $caseId);
        $this->withHeaders($agentHeaders)->postJson("/api/admin/support/cases/$caseId/reply",['body'=>'Snapshot reply from support.'])->assertOk();
        $message=DB::table('support_case_messages')->where('support_case_id',$caseId)->where('actor_user_id',$agent->id)->first();
        $event=DB::table('support_case_events')->where('support_case_id',$caseId)->where('event','staff_replied')->first();
        $this->assertNotNull($message);$this->assertNotNull($event);$this->assertSame($agent->name,$message->actor_name_snapshot);$this->assertSame($agent->name,$event->actor_name_snapshot);
        User::query()->whereKey($agent->id)->delete();
        $this->assertSame($agent->id,(int)DB::table('support_case_messages')->where('id',$message->id)->value('actor_user_id'));
        $this->assertSame($agent->id,(int)DB::table('support_case_events')->where('id',$event->id)->value('actor_user_id'));
        $messageFailed=false;try{DB::table('support_case_messages')->where('id',$message->id)->update(['body'=>'tampered']);}catch(\Throwable){$messageFailed=true;}
        $eventFailed=false;try{DB::table('support_case_events')->where('id',$event->id)->delete();}catch(\Throwable){$eventFailed=true;}
        $this->assertTrue($messageFailed);$this->assertTrue($eventFailed);
    }

    public function test_property_detail_exposes_advertiser_rating_and_public_comment_count(): void
    {
        [$advertiser]=$this->user('s10-detail-ad@example.test','+967720000020');
        [, $viewerHeaders]=$this->user('s10-detail-viewer@example.test','+967720000021');
        $listing=$this->publishedListing($advertiser,'Community detail');
        $this->withHeaders($viewerHeaders)->postJson("/api/properties/{$listing->id}/comments",['body'=>'Visible comment.'])->assertCreated();
        $this->withHeaders($viewerHeaders)->putJson("/api/advertisers/{$advertiser->id}/rating",['rating'=>4,'property_id'=>$listing->id])->assertCreated();
        $this->getJson("/api/properties/{$listing->id}")->assertOk()
            ->assertJsonPath('data.advertiser.id',$advertiser->id)
            ->assertJsonPath('data.advertiser.rating_average',4)
            ->assertJsonPath('data.advertiser.rating_count',1)
            ->assertJsonPath('data.community.comments_count',1);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Stage 10 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        $sync=[];foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($sync);
        $plain='re10_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'stage10-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function publishedListing(User $advertiser,string $title): Property
    {
        $asset=PropertyAsset::query()->create([
            'created_by_user_id'=>$advertiser->id,'identity_hash'=>hash('sha256',$advertiser->email.'|'.$title),'identity_version'=>1,
            'property_type'=>'house','canonical_address'=>'Stage 10 Address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,
            'area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,'status'=>'active',
        ]);
        return Property::query()->create([
            'user_id'=>$advertiser->id,'property_asset_id'=>$asset->id,'owner_key'=>null,'title'=>$title,'description'=>'Stage 10 published listing',
            'purpose'=>'sale','type'=>'house','price'=>55000000,'currency'=>'YER','area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,
            'address'=>'Stage 10 Address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now(),
            'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ]);
    }

    private function claimSupportTask(array $headers, string $type, int $sourceId): void
    {
        $queue=$this->withHeaders($headers)->getJson("/api/admin/workspace/tasks?scope=inbox&type=$type")->assertOk();
        $task=collect($queue->json('data'))->first(fn(array $item):bool=>(int)$item['source_id']===$sourceId);
        $this->assertNotNull($task);
        $this->withHeaders($headers)->postJson('/api/admin/workspace/tasks/'.(int)$task['id'].'/claim')->assertOk();
    }
}
