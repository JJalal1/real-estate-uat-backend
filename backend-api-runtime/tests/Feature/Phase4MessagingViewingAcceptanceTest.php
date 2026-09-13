<?php
namespace Tests\Feature;

use App\Models\Developer;
use App\Models\Development;
use App\Models\DevelopmentUnit;
use App\Models\PrivateMessage;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use App\Models\ViewingBooking;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Phase4MessagingViewingAcceptanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_property_conversation_is_reused_private_and_message_retries_are_idempotent(): void
    {
        [$owner,$ownerHeaders]=$this->user('p4-owner@example.test','+967760000001');
        [$buyer,$buyerHeaders]=$this->user('p4-buyer@example.test','+967760000002');
        [, $outsiderHeaders]=$this->user('p4-outsider@example.test','+967760000003');
        $property=$this->property($owner,'Phase 4 messaging');

        $first=$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertCreated();
        $threadId=(int)$first->json('data.id');
        $this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertOk()->assertJsonPath('data.id',$threadId);

        $payload=['body'=>'مرحبا، أريد تنسيق المعاينة.','client_message_id'=>'p4-msg-retry-0001'];
        $sent=$this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",$payload)->assertCreated();
        $messageId=(int)$sent->json('data.id');
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",$payload)->assertOk()->assertJsonPath('data.id',$messageId);
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",[
            'body'=>'نص مختلف يجب ألا يستخدم نفس المفتاح.',
            'client_message_id'=>'p4-msg-retry-0001',
        ])->assertConflict();
        $this->assertSame(1,PrivateMessage::query()->where('thread_id',$threadId)->where('client_message_id','p4-msg-retry-0001')->count());
        $this->assertDatabaseCount('user_notifications',1);

        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'   ','client_message_id'=>'p4-msg-blank-0001'])->assertUnprocessable();
        $this->withHeaders($outsiderHeaders)->getJson("/api/messages/threads/$threadId")->assertNotFound();
        $this->withHeaders($outsiderHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'no access'])->assertNotFound();

        $ownerInbox=$this->withHeaders($ownerHeaders)->getJson('/api/messages/threads')->assertOk();
        $this->assertSame(1,(int)$ownerInbox->json('data.0.unread_count'));
        $this->withHeaders($ownerHeaders)->getJson("/api/messages/threads/$threadId")->assertOk();
        $this->withHeaders($ownerHeaders)->getJson('/api/messages/threads')->assertOk()->assertJsonPath('data.0.unread_count',0);
    }

    public function test_conversation_returns_latest_page_and_can_load_older_messages_without_overlap(): void
    {
        [$owner,]=$this->user('p4-page-owner@example.test','+967760000010');
        [$buyer,$buyerHeaders]=$this->user('p4-page-buyer@example.test','+967760000011');
        $property=$this->property($owner,'Phase 4 pagination');
        $threadId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertCreated()->json('data.id');

        for($i=1;$i<=105;$i++){
            PrivateMessage::query()->create([
                'thread_id'=>$threadId,
                'sender_user_id'=>$buyer->id,
                'sender_name_snapshot'=>$buyer->name,
                'client_message_id'=>'p4-page-'.str_pad((string)$i,4,'0',STR_PAD_LEFT),
                'body'=>'Page message '.$i,
                'created_at'=>now()->addSeconds($i),
            ]);
        }

        $latest=$this->withHeaders($buyerHeaders)->getJson("/api/messages/threads/$threadId")->assertOk()
            ->assertJsonPath('data.pagination.has_more',true);
        $latestRows=$latest->json('data.messages');
        $this->assertCount(100,$latestRows);
        $this->assertSame('Page message 6',$latestRows[0]['body']);
        $this->assertSame('Page message 105',$latestRows[99]['body']);
        $before=(int)$latest->json('data.pagination.next_before_id');
        $this->assertSame((int)$latestRows[0]['id'],$before);

        $older=$this->withHeaders($buyerHeaders)->getJson("/api/messages/threads/$threadId?before_id=$before")->assertOk()
            ->assertJsonPath('data.pagination.has_more',false);
        $olderRows=$older->json('data.messages');
        $this->assertCount(5,$olderRows);
        $this->assertSame('Page message 1',$olderRows[0]['body']);
        $this->assertSame('Page message 5',$olderRows[4]['body']);
        $this->assertEmpty(array_intersect(
            array_column($latestRows,'id'),
            array_column($olderRows,'id'),
        ));
    }

    public function test_unpublished_property_blocks_new_contact_and_viewing_but_preserves_existing_conversation_history(): void
    {
        [$owner,]=$this->user('p4-owner2@example.test','+967760000004');
        [, $buyerHeaders]=$this->user('p4-buyer2@example.test','+967760000005');
        $property=$this->property($owner,'Phase 4 unavailable');
        $threadId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->json('data.id');
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'رسالة قبل إيقاف الإعلان','client_message_id'=>'p4-before-unpublish'])->assertCreated();

        $property->forceFill(['status'=>'draft'])->save();
        $this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/conversation")->assertNotFound();
        $this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/viewings",$this->window(2,10))->assertNotFound();
        $this->withHeaders($buyerHeaders)->getJson("/api/messages/threads/$threadId")->assertOk()->assertJsonPath('data.thread.property_status','draft');
        $this->withHeaders($buyerHeaders)->postJson("/api/messages/threads/$threadId/messages",['body'=>'السجل يبقى قابلاً للمراسلة','client_message_id'=>'p4-after-unpublish'])->assertCreated();
    }

    public function test_host_reschedule_requires_requester_acceptance_and_cannot_be_self_confirmed_by_host(): void
    {
        [$owner,$ownerHeaders]=$this->user('p4-owner3@example.test','+967760000006');
        [, $buyerHeaders]=$this->user('p4-buyer3@example.test','+967760000007');
        $property=$this->property($owner,'Phase 4 reschedule');
        $bookingId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/viewings",$this->window(3,11))->assertCreated()->json('data.id');

        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/reschedule",$this->window(4,14)+['note'=>'هذا الوقت أنسب'])->assertOk()
            ->assertJsonPath('data.status','requested')
            ->assertJsonPath('data.awaiting_requester_confirmation',true)
            ->assertJsonPath('data.can_confirm',false)
            ->assertJsonPath('data.can_decline',false);
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/decline",['note'=>'لن أستطيع'])->assertConflict();

        $this->withHeaders($buyerHeaders)->getJson("/api/bookings/$bookingId")->assertOk()->assertJsonPath('data.can_accept_reschedule',true);
        $this->withHeaders($buyerHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertOk()->assertJsonPath('data.status','confirmed');
        $this->assertDatabaseHas('viewing_booking_events',['viewing_booking_id'=>$bookingId,'event'=>'reschedule_accepted','to_status'=>'confirmed']);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$owner->id,'type'=>'booking_reschedule_accepted']);
    }

    public function test_unassigned_development_reschedule_acceptance_assigns_the_proposing_manager_as_host(): void
    {
        [$manager,$managerHeaders]=$this->user('p4-manager@example.test','+967760000012',['regions_manager']);
        [, $buyerHeaders]=$this->user('p4-unit-buyer@example.test','+967760000013');
        $unit=$this->developmentUnit($manager);
        $bookingId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/development-units/{$unit->id}/viewings",$this->window(7,10))->assertCreated()->json('data.id');

        ViewingBooking::query()->whereKey($bookingId)->update(['host_user_id'=>null,'host_name_snapshot'=>null]);
        $this->withHeaders($managerHeaders)->postJson("/api/bookings/$bookingId/reschedule",$this->window(8,12)+['note'=>'موعد بديل'])->assertOk()
            ->assertJsonPath('data.awaiting_requester_confirmation',true)
            ->assertJsonPath('data.host_user_id',null);
        $this->withHeaders($buyerHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertOk()
            ->assertJsonPath('data.status','confirmed')
            ->assertJsonPath('data.host_user_id',$manager->id);
        $this->assertDatabaseHas('viewing_bookings',['id'=>$bookingId,'host_user_id'=>$manager->id,'status'=>'confirmed']);
    }

    public function test_terminal_viewing_state_cannot_be_reopened_or_mutated(): void
    {
        [$owner,$ownerHeaders]=$this->user('p4-owner4@example.test','+967760000008');
        [, $buyerHeaders]=$this->user('p4-buyer4@example.test','+967760000009');
        $property=$this->property($owner,'Phase 4 terminal');
        $bookingId=(int)$this->withHeaders($buyerHeaders)->postJson("/api/properties/{$property->id}/viewings",$this->window(5,9))->assertCreated()->json('data.id');
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertOk();
        ViewingBooking::query()->whereKey($bookingId)->update(['starts_at'=>now()->subHours(2),'ends_at'=>now()->subHour()]);
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/complete")->assertOk()->assertJsonPath('data.status','completed');

        $this->withHeaders($buyerHeaders)->postJson("/api/bookings/$bookingId/cancel",['reason'=>'too late'])->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/decline",['note'=>'too late'])->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/reschedule",$this->window(6,12))->assertConflict();
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertConflict();
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create([
            'name'=>'Phase 4 User',
            'email'=>$email,
            'phone'=>$phone,
            'phone_verified_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,
            'password'=>Hash::make(uniqid('phase4-fixture-',true)),
        ]);
        $sync=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){
            $role=Role::query()->where('key',$key)->firstOrFail();
            $sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];
        }
        $user->roles()->sync($sync);
        $plain='p4_'.substr(hash('sha512',$email),0,78);
        $user->apiTokens()->create(['name'=>'phase4-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function property(User $owner,string $title): Property
    {
        $asset=PropertyAsset::query()->create(['created_by_user_id'=>$owner->id,'identity_hash'=>hash('sha256',$title.uniqid('',true)),'identity_version'=>1,'property_type'=>'apartment','canonical_address'=>'Phase 4 address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,'area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'status'=>'active']);
        return Property::query()->create(['user_id'=>$owner->id,'property_asset_id'=>$asset->id,'title'=>$title,'description'=>'Phase 4 published listing','purpose'=>'sale','type'=>'apartment','price'=>10000000,'currency'=>'YER','area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'address'=>'Phase 4 address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now()]);
    }

    private function developmentUnit(User $manager): DevelopmentUnit
    {
        $suffix=strtolower(substr(hash('sha1',(string)$manager->id),0,8));
        $developer=Developer::query()->create([
            'name'=>'Phase 4 Developer',
            'slug'=>'p4-dev-'.$suffix,
            'status'=>'active',
            'created_by_user_id'=>$manager->id,
            'created_by_name_snapshot'=>$manager->name,
        ]);
        $development=Development::query()->create([
            'developer_id'=>$developer->id,
            'created_by_user_id'=>$manager->id,
            'created_by_name_snapshot'=>$manager->name,
            'name'=>'Phase 4 Project',
            'slug'=>'p4-project-'.$suffix,
            'status'=>'published',
            'completion_status'=>'completed',
            'address'=>'Phase 4 project address',
            'published_by_user_id'=>$manager->id,
            'published_by_name_snapshot'=>$manager->name,
            'published_at'=>now(),
        ]);
        return DevelopmentUnit::query()->create([
            'development_id'=>$development->id,
            'code'=>'P4-1',
            'title'=>'Phase 4 Unit',
            'unit_type'=>'apartment',
            'area_m2'=>100,
            'price'=>1000000,
            'currency'=>'YER',
            'status'=>'available',
        ]);
    }

    private function window(int $days,int $hour): array
    {
        $start=now()->addDays($days)->setTime($hour,0,0);
        $end=$start->copy()->addHour();
        return ['starts_at'=>$start->toIso8601String(),'ends_at'=>$end->toIso8601String(),'timezone'=>'UTC'];
    }
}
