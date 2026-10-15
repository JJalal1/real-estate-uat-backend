<?php
namespace Tests\Feature;

use App\Models\Developer;
use App\Models\Development;
use App\Models\DevelopmentUnit;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use App\Models\ViewingBooking;
use App\Models\ViewingBookingEvent;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class Stage13BookingsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_retired_property_viewing_never_creates_a_booking_conversation_or_notification(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner@example.test','+967750000001');
        [, $requesterHeaders]=$this->user('s13-requester@example.test','+967750000002');
        [, $outsiderHeaders]=$this->user('s13-outsider@example.test','+967750000003');
        $property=$this->property($owner,'Retired viewing');
        foreach ([$ownerHeaders,$requesterHeaders,$outsiderHeaders] as $headers) {
            $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/viewings",$this->window(2,10))
                ->assertStatus(410)->assertJsonPath('code','viewings_retired');
        }
        foreach (['viewing_bookings','viewing_booking_events','message_threads','private_messages','user_notifications'] as $table) $this->assertDatabaseCount($table,0);
    }

    public function test_all_legacy_booking_actions_are_retired_and_do_not_change_history(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner2@example.test','+967750000004');
        [$first,$firstHeaders]=$this->user('s13-first@example.test','+967750000005');
        [, $outsiderHeaders]=$this->user('s13-outsider2@example.test','+967750000006');
        $property=$this->property($owner,'Legacy history');
        $booking=$this->legacyBooking($owner,$first,$property);
        $before=$booking->fresh()->getRawOriginal();
        foreach ([$ownerHeaders,$firstHeaders,$outsiderHeaders] as $headers) {
            $this->withHeaders($headers)->getJson("/api/bookings/{$booking->id}")->assertStatus(410);
            foreach (['confirm','decline','cancel','reschedule','complete'] as $action) {
                $this->withHeaders($headers)->postJson("/api/bookings/{$booking->id}/$action",$this->window(4,12)+['reason'=>'legacy','note'=>'legacy'])->assertStatus(410);
            }
        }
        $this->assertSame($before,$booking->fresh()->getRawOriginal());
        $this->assertDatabaseCount('viewing_booking_events',0);
        $this->assertDatabaseCount('user_notifications',0);
    }

    public function test_development_viewing_and_lists_are_retired_without_exposing_a_calendar(): void
    {
        [$manager,$managerHeaders]=$this->user('s13-manager@example.test','+967750000007',['regions_manager']);
        [, $requesterHeaders]=$this->user('s13-unit-user@example.test','+967750000008');
        [$unitA,$unitB]=$this->developmentUnits($manager);
        $unitB->forceFill(['status'=>'sold'])->save();
        foreach ([$unitA,$unitB] as $unit) {
            $this->withHeaders($requesterHeaders)->postJson("/api/development-units/{$unit->id}/viewings",$this->window(4,13))->assertStatus(410);
        }
        foreach (['mine','managed'] as $list) $this->withHeaders($managerHeaders)->getJson('/api/bookings/'.$list)->assertStatus(410);
        $this->withHeaders(['Authorization'=>''])->getJson('/api/bookings/mine')->assertUnauthorized();
        $this->assertDatabaseCount('viewing_bookings',0);
        $this->assertDatabaseCount('message_threads',0);
    }

    public function test_retirement_preserves_immutable_booking_event_history(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner3@example.test','+967750000009');
        [$requester]=$this->user('s13-reschedule@example.test','+967750000010');
        $property=$this->property($owner,'Legacy immutable history');
        $booking=$this->legacyBooking($owner,$requester,$property);
        $event=ViewingBookingEvent::query()->create(['viewing_booking_id'=>$booking->id,'actor_user_id'=>$requester->id,
            'actor_name_snapshot'=>$requester->name,'event'=>'requested','to_status'=>'requested','created_at'=>now()->subDay()]);
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/{$booking->id}/reschedule",$this->window(7,15))->assertStatus(410);
        try{DB::table('viewing_booking_events')->where('id',$event->id)->update(['event'=>'tampered']);$this->fail('Immutable event update was allowed.');}catch(QueryException){}
        try{DB::table('viewing_booking_events')->where('id',$event->id)->delete();$this->fail('Immutable event delete was allowed.');}catch(QueryException){}
        $this->assertDatabaseHas('viewing_booking_events',['id'=>$event->id,'event'=>'requested']);
        $this->assertDatabaseCount('viewing_bookings',1);
    }

    public function test_booking_permission_and_prior_stage_protections_exist(): void
    {
        foreach(['viewing_bookings','viewing_booking_events','message_threads','message_thread_participants','private_messages','developers','private_message_access_events','support_case_events'] as $table)$this->assertTrue(Schema::hasTable($table));
        $this->assertTrue(Schema::hasColumn('viewing_bookings','message_thread_id'));
        $this->assertDatabaseHas('permissions',['key'=>'bookings.manage']);
        $support=Role::query()->where('key','support_manager')->firstOrFail();$permission=DB::table('permissions')->where('key','bookings.manage')->value('id');
        $this->assertTrue(DB::table('role_permission')->where('role_id',$support->id)->where('permission_id',$permission)->exists());
        $this->assertDatabaseHas('permissions',['key'=>'developments.manage']);$this->assertDatabaseHas('permissions',['key'=>'conversations.review_private']);
    }

    private function legacyBooking(User $owner, User $requester, Property $property): ViewingBooking
    {
        return ViewingBooking::query()->create(['reference'=>'LEGACY-'.$property->id,'target_type'=>'property','target_id'=>$property->id,
            'target_title_snapshot'=>$property->title,'requester_user_id'=>$requester->id,'requester_name_snapshot'=>$requester->name,
            'host_user_id'=>$owner->id,'host_name_snapshot'=>$owner->name,'starts_at'=>now()->addDay(),'ends_at'=>now()->addDay()->addHour(),
            'timezone'=>'UTC','status'=>'confirmed']);
    }

    private function user(string $email,string $phone,array $roles=[]): array
    {
        $user=User::query()->create(['name'=>'Stage 13 User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make('StrongPass123!')]);
        $sync=[];foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){$role=Role::query()->where('key',$key)->firstOrFail();$sync[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];}$user->roles()->sync($sync);
        $plain='re13_'.substr(hash('sha512',$email),0,78);$user->apiTokens()->create(['name'=>'stage13-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function property(User $owner,string $title): Property
    {
        $asset=PropertyAsset::query()->create(['created_by_user_id'=>$owner->id,'identity_hash'=>hash('sha256',$title.uniqid('',true)),'identity_version'=>1,'property_type'=>'apartment','canonical_address'=>'Stage 13 address','canonical_latitude'=>15.3694,'canonical_longitude'=>44.1910,'area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'status'=>'active']);
        return Property::query()->create(['user_id'=>$owner->id,'property_asset_id'=>$asset->id,'title'=>$title,'description'=>'Stage 13 published listing','purpose'=>'sale','type'=>'apartment','price'=>10000000,'currency'=>'YER','area_m2'=>120,'bedrooms'=>3,'bathrooms'=>2,'address'=>'Stage 13 address','latitude'=>15.3694,'longitude'=>44.1910,'status'=>'published','review_status'=>'approved','published_at'=>now()]);
    }

    private function developmentUnits(User $manager): array
    {
        $developer=Developer::query()->create(['name'=>'Stage 13 Developer','slug'=>'s13-dev-'.strtolower(substr(hash('sha1',(string)$manager->id),0,8)),'status'=>'active','created_by_user_id'=>$manager->id,'created_by_name_snapshot'=>$manager->name]);
        $project=Development::query()->create(['developer_id'=>$developer->id,'created_by_user_id'=>$manager->id,'created_by_name_snapshot'=>$manager->name,'name'=>'Stage 13 Project','slug'=>'s13-project-'.strtolower(substr(hash('sha1',(string)$manager->id),0,8)),'status'=>'published','completion_status'=>'completed','address'=>'Stage 13 project address','published_by_user_id'=>$manager->id,'published_by_name_snapshot'=>$manager->name,'published_at'=>now()]);
        $a=DevelopmentUnit::query()->create(['development_id'=>$project->id,'code'=>'A-1','title'=>'Unit A','unit_type'=>'apartment','area_m2'=>100,'price'=>1000000,'currency'=>'YER','status'=>'available']);
        $b=DevelopmentUnit::query()->create(['development_id'=>$project->id,'code'=>'B-1','title'=>'Unit B','unit_type'=>'apartment','area_m2'=>110,'price'=>1100000,'currency'=>'YER','status'=>'available']);return [$a,$b];
    }

    private function window(int $days,int $hour): array
    {
        $start=now()->addDays($days)->setTime($hour,0,0);$end=$start->copy()->addHour();return ['starts_at'=>$start->toIso8601String(),'ends_at'=>$end->toIso8601String(),'timezone'=>'UTC'];
    }
}
