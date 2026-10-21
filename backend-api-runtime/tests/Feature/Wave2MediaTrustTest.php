<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\Role;
use App\Models\User;
use App\Models\ListingReview;
use App\Services\ListingImageService;
use App\Services\ListingWatermarkService;
use App\Services\PropertyIdentityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Wave2MediaTrustTest extends TestCase
{
    use RefreshDatabase;

    public function test_media_reviews_follow_claim_permissions_preserve_ads_and_are_idempotent(): void
    {
        [$owner,$oh]=$this->user('w2-image-owner@example.test','+967731200001');
        [$agent,$ah]=$this->user('w2-image-agent@example.test','+967731200002',['support_agent']);
        [, $bh]=$this->user('w2-image-agent-b@example.test','+967731200003',['support_agent']);
        $ad=$this->publishedListing($owner,'Image review');
        $ad->forceFill(['status'=>'draft','review_status'=>'submitted','review_assigned_to_user_id'=>null])->save();
        $image=$ad->images()->create(['path'=>'listing-originals/test/source.jpg','sort_order'=>0,'is_primary'=>true]);
        $url="/api/admin/listing-review/listings/$ad->id/media-review";
        $payload=['image_id'=>$image->id,'decision'=>'uncertain','reason'=>'أرض فارغة تحتاج توضيحًا من المعلن.'];
        $this->withHeaders($oh)->postJson($url,$payload)->assertForbidden();
        $this->withHeaders($ah)->postJson($url,$payload)->assertConflict();
        $this->withHeaders($ah)->postJson("/api/admin/listing-review/listings/$ad->id/start")->assertOk();
        $this->withHeaders($bh)->postJson($url,$payload)->assertConflict();
        $one=$this->withHeaders($ah)->postJson($url,$payload)->assertOk()->assertJsonPath('data.checker','human_review');
        $this->withHeaders($ah)->postJson($url,$payload)->assertOk()->assertJsonPath('data.review_id',$one->json('data.review_id'));
        $this->assertSame(1,ListingReview::where('action','media_relevance_review')->count());
        $this->assertSame('under_review',$ad->fresh()->review_status);
        $this->assertDatabaseHas('property_images',['id'=>$image->id,'path'=>$image->path]);
        $this->withHeaders($ah)->getJson("/api/admin/listing-review/listings/$ad->id")->assertOk()->assertJsonPath('data.images.0.relevance_review.decision','uncertain');
        $payload['decision']='unrelated';$payload['reason']='الصورة لمنتج غير مرتبط بالعقار المعروض.';
        $this->withHeaders($ah)->postJson($url,$payload)->assertOk();
        $this->assertSame('under_review',$ad->fresh()->review_status);
        $this->assertDatabaseCount('property_images',1);
        $this->assertDatabaseHas('audit_logs',['action'=>'listing.media_relevance_reviewed','actor_user_id'=>$agent->id]);
        // A replaced image may never inherit the old file's assessment.
        $image->update(['path'=>'listing-originals/test/replaced.jpg']);
        $this->withHeaders($ah)->getJson("/api/admin/listing-review/listings/$ad->id")->assertOk()->assertJsonPath('data.images.0.relevance_review.decision','pending');
        $other=$this->publishedListing($owner,'Other listing')->images()->create(['path'=>'listing-originals/other.jpg']);
        $payload['image_id']=$other->id;
        $this->withHeaders($ah)->postJson($url,$payload)->assertNotFound();
    }

    public function test_similar_street_photos_and_dimensions_are_not_exact_house_identity(): void
    {
        [$a]=$this->user('w2-near-a@example.test','+967731200004');
        [$b]=$this->user('w2-near-b@example.test','+967731200005');
        $first=$this->publishedListing($a,'Similar A');
        $first->forceFill(['address'=>'صنعاء حدة جوار السوق','area_m2'=>220,'latitude'=>15.36,'longitude'=>44.19])->save();
        $second=$this->publishedListing($b,'Similar B');
        $second->forceFill(['status'=>'draft','review_status'=>'draft','address'=>'صنعاء حدة جوار السوق','area_m2'=>221,'latitude'=>15.36007,'longitude'=>44.19004])->save();
        $result=app(PropertyIdentityService::class)->evaluate($second,$b);
        $this->assertSame('possible_duplicate',$result['decision']);
        $this->assertNotContains('same_explicit_house_reference',$result['signals']);
        $this->assertSame('draft',$second->fresh()->status);
    }

    public function test_watermark_remains_off_without_approval_and_invalid_activation_fails_closed(): void
    {
        $service=app(ListingWatermarkService::class);
        $this->assertSame('v1',$service->version());
        config(['listing_media.watermark.enabled'=>true,'listing_media.watermark.approved_sha256'=>'']);
        $this->expectException(\RuntimeException::class);
        $service->version();
    }

    public function test_pinned_vector_pipeline_keeps_original_private_and_sanitizes_all_cached_variants(): void
    {
        Storage::fake('local');Storage::fake('public');
        $resources=sys_get_temp_dir().'/aqer-synthetic-'.bin2hex(random_bytes(8));
        mkdir($resources.'/brand',0700,true);
        $geometry=json_encode(['approval'=>'owner-approved','layers'=>[['polygons'=>[[[0.1,0.1],[0.9,0.1],[0.9,0.9],[0.1,0.9]]],'holes'=>[]]]]);
        file_put_contents($resources.'/brand/aqer-approved.json',$geometry);
        $originalResourcePath=resource_path();$this->app->useResourcePath($resources);
        try {
            config(['listing_media.watermark.enabled'=>true,'listing_media.watermark.approved_sha256'=>hash('sha256',$geometry)]);
            $bytes=$this->jpegWithExif(6);$service=app(ListingImageService::class);
            $path=$service->store(UploadedFile::fake()->createWithContent('camera.jpg',$bytes),'listing-originals/wave2');
            $this->assertSame($bytes,Storage::disk('local')->get($path));Storage::disk('public')->assertMissing($path);
            foreach(array_keys(config('listing_media.variants')) as $name) {
                $target=$service->variantPath($path,$name);$encoded=Storage::disk('local')->get($target);
                $this->assertStringContainsString('/v2-wm-',$target);
                $this->assertStringNotContainsString('Exif',$encoded);$this->assertStringNotContainsString('PRIVATE_CAMERA',$encoded);
                $info=getimagesizefromstring($encoded);$this->assertGreaterThan($info[0],$info[1]);
                $this->assertSame('image/jpeg',$info['mime']);
                $hash=hash('sha256',$encoded);
                // Cached delivery must work even when re-reading the private original would fail.
                Storage::disk('local')->delete($path);
                $service->response($path,$name,true);
                $this->assertSame($hash,hash('sha256',Storage::disk('local')->get($target)));
                Storage::disk('local')->put($path,$bytes);
            }
            $image=imagecreatefromstring(Storage::disk('local')->get($service->variantPath($path,'gallery')));
            $this->assertNotFalse($image);imagedestroy($image);
            $this->assertSame(0,DB::table('property_sai_terms')->count());
        } finally {
            $this->app->useResourcePath($originalResourcePath);unlink($resources.'/brand/aqer-approved.json');rmdir($resources.'/brand');rmdir($resources);
        }
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

}
