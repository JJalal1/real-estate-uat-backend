<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\Role;
use App\Models\User;
use App\Services\ListingImageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class UserWorkMediaTest extends TestCase
{
    use RefreshDatabase;

    public function test_uncertain_checkpoint_retry_is_idempotent_and_cannot_change_its_body(): void
    {
        [, $headers]=$this->actor('checkpoint');$key=(string)Str::uuid();$operation=(string)Str::uuid();
        $payload=['checkpoint_key'=>$operation,'media_version'=>1,'type'=>'shop','fields'=>['title'=>'كتبت الإعلان دون شبكة'],
            'latitude'=>13.96,'longitude'=>44.18,'image_order'=>[]];
        $url='/api/listing-editor-drafts/'.$key;
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk()->assertJsonPath('data.revision',1);
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk()->assertJsonPath('data.revision',1);
        $changed=$payload;$changed['fields']['title']='تعديل آخر';
        $this->withHeaders($headers)->putJson($url,['payload'=>$changed,'expected_revision'=>0])->assertConflict();
        $this->withHeaders($headers)->getJson($url)->assertJsonPath('data.payload.fields.title','كتبت الإعلان دون شبكة')->assertJsonPath('data.payload.latitude',13.96);
        $this->assertDatabaseCount('listing_editor_drafts',1);$this->assertDatabaseCount('properties',0);
    }

    public function test_each_file_retries_without_duplicates_and_removed_keys_cannot_resurrect(): void
    {
        Storage::fake('local');Storage::fake('public');
        [, $headers]=$this->actor('files');[, $other]=$this->actor('other');
        $key=(string)Str::uuid();$first=(string)Str::uuid();$second=(string)Str::uuid();$url='/api/listing-editor-drafts/'.$key;
        $payload=['checkpoint_key'=>(string)Str::uuid(),'media_version'=>1,'type'=>'shop','image_order'=>[$first,$second],'fields'=>[]];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        $image=UploadedFile::fake()->image('phone.jpg',160,80);
        $this->withHeaders($headers)->post($url.'/images/'.$first,['image'=>$image,'expected_revision'=>1])->assertOk()->assertJsonPath('data.revision',2);
        $this->withHeaders($headers)->post($url.'/images/'.$first,['image'=>$image,'expected_revision'=>1])->assertOk()->assertJsonPath('data.revision',2);
        $this->withHeaders($headers)->post($url.'/images/'.$first,['image'=>UploadedFile::fake()->image('different.jpg',40,40),'expected_revision'=>2])->assertConflict();
        $this->withHeaders($headers)->post($url.'/images/'.$second,['image'=>UploadedFile::fake()->image('corrupt.jpg')->size(9000),'expected_revision'=>2])->assertUnprocessable();
        $this->withHeaders($headers)->getJson($url)->assertJsonCount(1,'data.images');
        $this->withHeaders($headers)->post($url.'/images/'.$second,['image'=>$image,'expected_revision'=>2])->assertOk()->assertJsonCount(2,'data.images');
        $this->assertCount(2,Storage::disk('local')->allFiles('editor-drafts'));
        $this->assertCount(0,Storage::disk('public')->allFiles());
        $this->withHeaders($other)->get($url.'/images/'.$first)->assertNotFound();
        $this->withHeaders($other)->post($url.'/images/'.$first,['image'=>$image,'expected_revision'=>3])->assertNotFound();
        $payload['checkpoint_key']=(string)Str::uuid();$payload['image_order']=[$second];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>3])->assertOk();
        $this->withHeaders($headers)->deleteJson($url.'/images/'.$first,['expected_revision'=>4])->assertOk()->assertJsonPath('data.revision',5);
        $this->withHeaders($headers)->deleteJson($url.'/images/'.$first,['expected_revision'=>4])->assertOk()->assertJsonPath('data.revision',5);
        $this->withHeaders($headers)->post($url.'/images/'.$first,['image'=>$image,'expected_revision'=>5])->assertConflict();
        $this->assertCount(1,Storage::disk('local')->allFiles('editor-drafts'));
    }

    public function test_public_variants_strip_real_exif_preserve_orientation_and_keep_original_private(): void
    {
        Storage::fake('local');Storage::fake('public');
        [$actor,$headers]=$this->actor('exif');
        $source=$this->jpegWithExif(6);
        $original=app(ListingImageService::class)->store(UploadedFile::fake()->createWithContent('phone.jpg',$source),'listing-originals/test');
        $this->assertSame($source,Storage::disk('local')->get($original));
        $property=$this->property($actor);$image=$property->images()->create(['path'=>$original,'sort_order'=>0,'is_primary'=>true]);
        $this->withHeaders(['Authorization'=>''])->get('/api/property-media/'.$image->id)->assertNotFound();
        // Isolated media-route fixture; publication/financial workflow guards are exercised by their original suites.
        Property::withoutEvents(fn()=>$property->update(['status'=>'published']));
        foreach (['card'=>640,'detail'=>1280,'gallery'=>1920,'zoom'=>3072] as $variant=>$edge) {
            $response=$this->withHeaders(['Authorization'=>''])->get('/api/property-media/'.$image->id.'?variant='.$variant)->assertOk()->assertHeader('Content-Type','image/jpeg');
            $bytes=$response->streamedContent();$info=getimagesizefromstring($bytes);
            $this->assertLessThanOrEqual($edge,max($info[0],$info[1]));
            $this->assertGreaterThan($info[0],$info[1]); // Landscape raw source becomes upright portrait.
            $this->assertStringNotContainsString('Exif',$bytes);$this->assertStringNotContainsString('PRIVATE_CAMERA',$bytes);
            $this->assertStringNotContainsString('GPS',$bytes);
        }
        $this->get('/api/property-media/'.$image->id.'?variant=original')->assertUnprocessable();
        $this->assertEquals(13.96,$property->fresh()->latitude);$this->assertEquals(44.18,$property->fresh()->longitude);
        $this->assertCount(0,Storage::disk('public')->allFiles());
    }

    public function test_real_jpeg_png_webp_are_decoded_and_unsupported_or_oversized_sources_fail_safely(): void
    {
        Storage::fake('local');$service=app(ListingImageService::class);
        foreach (['jpeg','png','webp'] as $format) {
            $image=imagecreatetruecolor(90,60);imagefill($image,0,0,imagecolorallocate($image,220,30,50));
            ob_start();('image'.$format)($image);$bytes=ob_get_clean();imagedestroy($image);
            $path=$service->store(UploadedFile::fake()->createWithContent('source.'.$format,$bytes),'listing-originals/formats');
            $this->assertSame($bytes,Storage::disk('local')->get($path));
            $this->assertSame(IMAGETYPE_JPEG,getimagesizefromstring(Storage::disk('local')->get($service->variantPath($path,'card')))[2]);
        }
        foreach (['not an image',"\0\0\0\x18ftypheicPRIVATE_CAMERA",str_repeat('x',8388609)] as $invalid) {
            try { $service->store(UploadedFile::fake()->createWithContent('phone.jpg',$invalid),'listing-originals/invalid');$this->fail('Invalid source accepted'); }
            catch (\Illuminate\Validation\ValidationException) { $this->assertCount(0,Storage::disk('local')->allFiles('listing-originals/invalid')); }
        }
    }

    public function test_order_primary_and_individual_removal_roundtrip_without_deleting_shared_originals(): void
    {
        Storage::fake('local');Storage::fake('public');[$actor,$headers]=$this->actor('order');
        $key=(string)Str::uuid();$keys=[(string)Str::uuid(),(string)Str::uuid(),(string)Str::uuid()];$url='/api/listing-editor-drafts/'.$key;
        $payload=['media_version'=>1,'checkpoint_key'=>(string)Str::uuid(),'type'=>'shop','purpose'=>'rent','image_order'=>$keys,'fields'=>['area'=>'65']];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        foreach ($keys as $i=>$imageKey) $this->withHeaders($headers)->post($url.'/images/'.$imageKey,['expected_revision'=>$i+1,'image'=>UploadedFile::fake()->image('source.jpg',80+$i,60)])->assertOk();
        $input=['listing_input_version'=>8,'title'=>'محل من صور الهاتف','type'=>'shop','purpose'=>'rent','price'=>75000,'monthly_rent'=>75000,'currency'=>'YER','area_value'=>65,'area_unit'=>'sqm','address'=>'صنعاء حدة شارع 14','latitude'=>15.3694,'longitude'=>44.191,'editor_draft_key'=>$key,'editor_draft_revision'=>4];
        $data=$this->withHeaders($headers)->postJson('/api/properties',$input)->assertCreated()->assertJsonCount(3,'data.images')->json('data');
        $ids=array_column($data['images'],'id');$property=Property::findOrFail($data['id']);
        $this->assertTrue((bool)$data['images'][0]['is_primary']);
        $checkpoint=$this->withHeaders($headers)->getJson($url)->assertOk()->json('data');
        $this->assertSame(array_map(fn($id)=>'property-'.$id,$ids),$checkpoint['payload']['image_order']);
        foreach ($keys as $i=>$token) $this->assertSame('property-'.$ids[$i],$checkpoint['payload']['promoted_image_keys'][$token]);
        // The create response was lost: the same request cannot create another listing or another photo row.
        $this->withHeaders($headers)->postJson('/api/properties',$input)->assertConflict();
        $this->assertDatabaseCount('properties',1);$this->assertDatabaseCount('property_images',3);
        $removed=PropertyImage::findOrFail($ids[1]);$shared=$this->property($actor);
        $shared->images()->create(['path'=>$removed->path,'sort_order'=>0]);
        $payload['checkpoint_key']=(string)Str::uuid();$payload['image_order']=['property-'.$ids[2],'property-'.$ids[0]];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>5,'property_id'=>$property->id])->assertOk();
        $input['editor_draft_revision']=6;
        $updated=$this->withHeaders($headers)->postJson('/api/properties/'.$property->id,$input)->assertOk()->json('data.images');
        $this->assertSame([$ids[2],$ids[0]],array_column($updated,'id'));$this->assertTrue((bool)$updated[0]['is_primary']);
        app(ListingImageService::class)->removeIfUnused($removed->path);Storage::disk('local')->assertExists($removed->path);
        $this->withHeaders($headers)->getJson($url)->assertJsonPath('data.payload.image_order',$payload['image_order']);
        $foreign=$shared->images()->firstOrFail();
        $payload['checkpoint_key']=(string)Str::uuid();$payload['image_order']=['property-'.$foreign->id];
        $this->withHeaders($headers)->putJson($url,['payload'=>$payload,'expected_revision'=>7,'property_id'=>$property->id])->assertUnprocessable();
        $this->withHeaders($headers)->getJson($url)->assertJsonPath('data.revision',7);
        $this->assertDatabaseCount('property_sai_terms',0);
    }

    public function test_all_eight_exif_orientations_preserve_the_expected_corner_order(): void
    {
        Storage::fake('local');$service=app(ListingImageService::class);
        $expected=[1=>[0,1,2,3],2=>[1,0,3,2],3=>[3,2,1,0],4=>[2,3,0,1],5=>[0,2,1,3],6=>[2,0,3,1],7=>[3,1,2,0],8=>[1,3,0,2]];
        $palette=[[255,0,0],[0,255,0],[0,0,255],[255,255,0]];
        foreach ($expected as $orientation=>$corners) {
            $path=$service->store(UploadedFile::fake()->createWithContent('rotation.jpg',$this->jpegWithExif($orientation)),'listing-originals/orientation');
            $image=imagecreatefromstring(Storage::disk('local')->get($service->variantPath($path,'card')));
            $w=imagesx($image);$h=imagesy($image);$actual=[];
            $this->assertSame($orientation>=5,$h>$w);
            foreach ([[10,10],[$w-11,10],[10,$h-11],[$w-11,$h-11]] as [$x,$y]) {
                $rgb=imagecolorsforindex($image,imagecolorat($image,$x,$y));$distances=[];
                foreach ($palette as [$r,$g,$b]) $distances[]=($rgb['red']-$r)**2+($rgb['green']-$g)**2+($rgb['blue']-$b)**2;
                $actual[]=array_search(min($distances),$distances,true);
            }
            imagedestroy($image);$this->assertSame($corners,$actual,'EXIF orientation '.$orientation);
        }
    }

    public function test_resumable_endpoints_are_off_by_default_and_ownership_is_enforced_when_enabled(): void
    {
        Storage::fake('local');
        [, $owner] = $this->actor('tus-owner');
        [, $other] = $this->actor('tus-other');
        $key = (string) Str::uuid();
        $photo = (string) Str::uuid();
        $url = '/api/listing-editor-drafts/'.$key;
        $payload = [
            'checkpoint_key'=>(string)Str::uuid(),
            'media_version'=>1,
            'type'=>'shop',
            'image_order'=>[$photo],
            'fields'=>[],
        ];
        $this->withHeaders($owner)->putJson($url,['payload'=>$payload,'expected_revision'=>0])->assertOk();
        $ticketUrl = $url.'/images/'.$photo.'/resumable-ticket';
        $body = [
            'expected_revision'=>1,
            'sha256'=>str_repeat('a', 64),
            'byte_length'=>2048,
            'mime'=>'image/png',
        ];
        $this->withHeaders($owner)->postJson($ticketUrl,$body)->assertNotFound();
        $this->withHeaders($owner)->postJson($url.'/images/'.$photo.'/resumable-finalize',['expected_revision'=>1])->assertNotFound();

        config(['listing_media.resumable_uploads_enabled'=>true]);
        // A different account cannot enumerate or reserve someone else's image.
        $this->withHeaders($other)->postJson($ticketUrl,$body)->assertNotFound();
        $this->assertDatabaseCount('listing_image_upload_intents',0);
        $this->withHeaders($owner)->postJson($ticketUrl,[...$body,'byte_length'=>8388609])->assertUnprocessable();
        $this->withHeaders($owner)->postJson($ticketUrl,[...$body,'mime'=>'text/plain'])->assertUnprocessable();
        $this->assertDatabaseCount('listing_image_upload_intents',0);
    }

    public function test_removing_uncommitted_image_cancels_ticket_and_expired_cleanup_deletes_only_orphans(): void
    {
        Storage::fake('local');
        [, $owner] = $this->actor('tus-cleanup-owner');
        $key = (string) Str::uuid();
        $imageKey = (string) Str::uuid();
        $url = '/api/listing-editor-drafts/'.$key;
        $this->withHeaders($owner)->putJson($url, [
            'payload'=>['media_version'=>1,'image_order'=>[$imageKey], 'fields'=>[]],
            'expected_revision'=>0,
        ])->assertOk();
        $draft = ListingEditorDraft::where('client_key', $key)->firstOrFail();
        $sha = str_repeat('c',64);
        $path = 'editor-drafts/'.$draft->user_id.'/'.$key.'/'.$imageKey.'-'.$sha.'.png';
        $intent = \App\Models\ListingImageUploadIntent::create([
            'user_id'=>$draft->user_id,'listing_editor_draft_id'=>$draft->id,
            'image_key'=>$imageKey,'path'=>$path,'sha256'=>$sha,'byte_length'=>300,
            'mime'=>'image/png','status'=>'pending',
            'signed_until'=>now()->subHours(3),'purge_after'=>now()->subMinute(),
        ]);
        Storage::disk('local')->put($path,'orphan');
        $this->withHeaders($owner)->deleteJson($url.'/images/'.$imageKey,[
            'expected_revision'=>1,
        ])->assertOk();
        $this->assertSame('canceled', $intent->fresh()->status);
        $result = app(\App\Services\ListingImageUploadIntentService::class)->purgeExpired();
        $this->assertSame(1,$result['removed']);
        Storage::disk('local')->assertMissing($path);
        $this->assertDatabaseMissing('listing_image_upload_intents',['id'=>$intent->id]);
    }

    public function test_upload_cleanup_never_deletes_media_referenced_by_a_committed_draft(): void
    {
        Storage::fake('local');
        [, $owner] = $this->actor('tus-cleanup-safe');
        $key = (string) Str::uuid();
        $imageKey = (string) Str::uuid();
        $url = '/api/listing-editor-drafts/'.$key;
        $this->withHeaders($owner)->putJson($url,[
            'payload'=>['media_version'=>1,'image_order'=>[$imageKey],'fields'=>[]],
            'expected_revision'=>0,
        ])->assertOk();
        $draft = ListingEditorDraft::where('client_key',$key)->firstOrFail();
        $sha = str_repeat('d',64);
        $path = 'editor-drafts/'.$draft->user_id.'/'.$key.'/'.$imageKey.'-'.$sha.'.png';
        Storage::disk('local')->put($path,'committed-data');
        $draft->images = [$imageKey=>$path]; $draft->save();
        $intent = \App\Models\ListingImageUploadIntent::create([
            'user_id'=>$draft->user_id,'listing_editor_draft_id'=>$draft->id,
            'image_key'=>$imageKey,'path'=>$path,'sha256'=>$sha,'byte_length'=>14,
            'mime'=>'image/png','status'=>'pending',
            'signed_until'=>now()->subHours(3),'purge_after'=>now()->subMinute(),
        ]);
        $result = app(\App\Services\ListingImageUploadIntentService::class)->purgeExpired();
        $this->assertSame(0,$result['removed']);
        $this->assertSame('complete',$intent->fresh()->status);
        Storage::disk('local')->assertExists($path);
    }

    private function jpegWithExif(int $orientation): string
    {
        $image=imagecreatetruecolor(800,400);
        foreach ([[0,0,399,199,255,0,0],[400,0,799,199,0,255,0],[0,200,399,399,0,0,255],[400,200,799,399,255,255,0]] as [$x1,$y1,$x2,$y2,$r,$g,$b]) {
            imagefilledrectangle($image,$x1,$y1,$x2,$y2,imagecolorallocate($image,$r,$g,$b));
        }
        ob_start();imagejpeg($image,null,92);$jpeg=ob_get_clean();imagedestroy($image);
        $make="PRIVATE_CAMERA\0";$gpsOffset=50+strlen($make);
        $tiff='II'.pack('vV',42,8).pack('v',3)
            .pack('vvVv',0x112,3,1,$orientation)."\0\0"
            .pack('vvVV',0x10f,2,strlen($make),50)
            .pack('vvVV',0x8825,4,1,$gpsOffset).pack('V',0).$make
            .pack('v',1).pack('vvV',1,2,2)."N\0\0\0".pack('V',0);
        $exif="Exif\0\0".$tiff;
        return substr($jpeg,0,2)."\xff\xe1".pack('n',strlen($exif)+2).$exif.substr($jpeg,2);
    }

    private function actor(string $name): array
    {
        $user=User::create(['name'=>'دلال اختبار','email'=>$name.'@media.example.test','phone'=>'+96777'.substr((string)crc32($name),0,7),
            'password'=>Hash::make('fixture-pass'),'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $user->roles()->sync([Role::where('key','registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        AccountVerificationProfile::create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','submitted_at'=>now(),'reviewed_at'=>now()]);
        $token='media_fixture_'.$name;$user->apiTokens()->create(['name'=>'test','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$token,'Accept'=>'application/json']];
    }

    private function property(User $user): Property
    {
        return Property::create(['user_id'=>$user->id,'title'=>'إعلان اختباري','type'=>'shop','purpose'=>'rent','price'=>75000,'currency'=>'YER',
            'address'=>'صنعاء حدة','latitude'=>13.96,'longitude'=>44.18,'status'=>'draft','review_status'=>'draft']);
    }
}
