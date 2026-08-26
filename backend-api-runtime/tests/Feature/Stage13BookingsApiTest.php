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

    public function test_published_listing_viewing_is_private_and_self_booking_is_blocked(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner@example.test','+967750000001');
        [$requester,$requesterHeaders]=$this->user('s13-requester@example.test','+967750000002');
        [, $outsiderHeaders]=$this->user('s13-outsider@example.test','+967750000003');
        $property=$this->property($owner,'Stage 13 listing A');$window=$this->window(2,10);
        $response=$this->withHeaders($requesterHeaders)->postJson("/api/properties/{$property->id}/viewings",$window+['note'=>'Please confirm this viewing.'])->assertCreated()->assertJsonPath('data.status','requested');
        $bookingId=(int)$response->json('data.id');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/{$property->id}/viewings",$window)->assertConflict();
        $this->withHeaders($outsiderHeaders)->getJson("/api/bookings/$bookingId")->assertNotFound();
        $this->withHeaders($requesterHeaders)->postJson("/api/bookings/$bookingId/confirm")->assertForbidden();
        $this->assertDatabaseHas('viewing_booking_events',['viewing_booking_id'=>$bookingId,'event'=>'requested']);
        $this->assertDatabaseHas('user_notifications',['user_id'=>$owner->id,'type'=>'viewing_requested','entity_id'=>$bookingId]);
        $this->assertSame($requester->id,(int)ViewingBooking::query()->findOrFail($bookingId)->requester_user_id);
    }

    public function test_confirmation_prevents_target_overlap_and_cancellation_releases_slot(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner2@example.test','+967750000004');
        [$first,$firstHeaders]=$this->user('s13-first@example.test','+967750000005');
        [, $secondHeaders]=$this->user('s13-second@example.test','+967750000006');
        $property=$this->property($owner,'Stage 13 listing B');$window=$this->window(3,11);
        $one=(int)$this->withHeaders($firstHeaders)->postJson("/api/properties/{$property->id}/viewings",$window)->assertCreated()->json('data.id');
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$one/confirm",['note'=>'Confirmed'])->assertOk()->assertJsonPath('data.status','confirmed');
        $two=(int)$this->withHeaders($secondHeaders)->postJson("/api/properties/{$property->id}/viewings",$window)->assertCreated()->json('data.id');
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$two/confirm")->assertConflict();
        $this->withHeaders($firstHeaders)->postJson("/api/bookings/$one/cancel",['reason'=>'Schedule changed'])->assertOk()->assertJsonPath('data.status','cancelled');
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$two/confirm")->assertOk()->assertJsonPath('data.status','confirmed');
        $this->assertDatabaseHas('user_notifications',['user_id'=>$first->id,'type'=>'booking_confirmed','entity_id'=>$one]);
    }

    public function test_development_manager_can_confirm_unit_viewing_and_requester_conflicts_are_blocked(): void
    {
        [$manager,$managerHeaders]=$this->user('s13-manager@example.test','+967750000007',['regions_manager']);
        [, $requesterHeaders]=$this->user('s13-unit-user@example.test','+967750000008');
        [$unitA,$unitB]=$this->developmentUnits($manager);
        $window=$this->window(4,13);
        $a=(int)$this->withHeaders($requesterHeaders)->postJson("/api/development-units/{$unitA->id}/viewings",$window)->assertCreated()->json('data.id');
        $this->withHeaders($managerHeaders)->getJson('/api/bookings/managed')->assertOk();
        $this->withHeaders($managerHeaders)->postJson("/api/bookings/$a/confirm")->assertOk()->assertJsonPath('data.host_user_id',$manager->id);
        $b=(int)$this->withHeaders($requesterHeaders)->postJson("/api/development-units/{$unitB->id}/viewings",$window)->assertCreated()->json('data.id');
        $this->withHeaders($managerHeaders)->postJson("/api/bookings/$b/confirm")->assertConflict();
        $unitB->forceFill(['status'=>'sold'])->save();
        $later=$this->window(5,14);$this->withHeaders($requesterHeaders)->postJson("/api/development-units/{$unitB->id}/viewings",$later)->assertNotFound();
    }

    public function test_reschedule_returns_to_requested_and_booking_event_history_is_immutable(): void
    {
        [$owner,$ownerHeaders]=$this->user('s13-owner3@example.test','+967750000009');
        [, $requesterHeaders]=$this->user('s13-reschedule@example.test','+967750000010');
        $property=$this->property($owner,'Stage 13 listing C');$booking=(int)$this->withHeaders($requesterHeaders)->postJson("/api/properties/{$property->id}/viewings",$this->window(6,9))->json('data.id');
        $this->withHeaders($ownerHeaders)->postJson("/api/bookings/$booking/confirm")->assertOk();
        $this->withHeaders($requesterHeaders)->postJson("/api/bookings/$booking/reschedule",$this->window(7,15)+['note'=>'New time please'])->assertOk()->assertJsonPath('data.status','requested');
        $this->assertDatabaseCount('viewing_booking_events',3);$event=ViewingBookingEvent::query()->where('viewing_booking_id',$booking)->firstOrFail();
        try{DB::table('viewing_booking_events')->where('id',$event->id)->update(['event'=>'tampered']);$this->fail('Immutable event update was allowed.');}catch(QueryException){}
        try{DB::table('viewing_booking_events')->where('id',$event->id)->delete();$this->fail('Immutable event delete was allowed.');}catch(QueryException){}
        $this->assertDatabaseHas('viewing_booking_events',['id'=>$event->id,'event'=>'requested']);
    }

    public function test_booking_permission_and_prior_stage_protections_exist(): void
    {
        foreach(['viewing_bookings','viewing_booking_events','developers','private_message_access_events','support_case_events'] as $table)$this->assertTrue(Schema::hasTable($table));
        $this->assertDatabaseHas('permissions',['key'=>'bookings.manage']);
        $support=Role::query()->where('key','support_manager')->firstOrFail();$permission=DB::table('permissions')->where('key','bookings.manage')->value('id');
        $this->assertTrue(DB::table('role_permission')->where('role_id',$support->id)->where('permission_id',$permission)->exists());
        $this->assertDatabaseHas('permissions',['key'=>'developments.manage']);$this->assertDatabaseHas('permissions',['key'=>'conversations.review_private']);
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
