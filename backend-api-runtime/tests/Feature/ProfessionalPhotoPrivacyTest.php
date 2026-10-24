<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Role;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\ProfessionalPhotoService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProfessionalPhotoPrivacyTest extends TestCase
{
    use RefreshDatabase;

    public function test_new_upload_is_private_sanitized_bounded_and_replacement_and_erasure_remove_it(): void
    {
        Storage::fake('local'); Storage::fake('public');
        $watermark = \Mockery::mock(\App\Services\ListingWatermarkService::class);
        $watermark->shouldNotReceive('apply');
        $this->app->instance(\App\Services\ListingWatermarkService::class,$watermark);
        [$actor,$bearer] = $this->actor();
        $source = $this->fixture();
        $this->withToken($bearer)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->createWithContent('synthetic.jpg',$source)])->assertOk();
        $path = $actor->fresh()->public_professional_photo_path;
        $this->assertStringStartsWith('professional-display/v1/',$path);
        Storage::disk('local')->assertExists($path);
        $this->assertSame([],Storage::disk('public')->allFiles());
        $bytes = Storage::disk('local')->get($path);
        $this->assertSafe($bytes);
        $this->assertNotSame($source,$bytes);
        $this->flushHeaders();
        $public = $this->get('/api/advertisers/'.$actor->id.'/photo')->assertOk()->assertHeader('Content-Type','image/jpeg');
        $this->assertSame($bytes,$public->streamedContent());
        $this->getJson('/api/advertisers/'.$actor->id.'/profile')->assertOk()->assertJsonMissingPath('data.public_professional_photo_path');
        $this->withToken($bearer)->post('/api/broker/profile/photo',['photo'=>UploadedFile::fake()->image('replacement.jpg',60,40)])->assertOk();
        Storage::disk('local')->assertMissing($path);
        $replacement = $actor->fresh()->public_professional_photo_path;
        Storage::disk('local')->assertExists($replacement);
        $this->withToken($bearer)->deleteJson('/api/account',['confirm_phrase'=>'حذف حسابي نهائيًا'])->assertOk();
        Storage::disk('local')->assertMissing($replacement);
        $this->flushHeaders();
        $this->get('/api/advertisers/'.$actor->id.'/photo')->assertNotFound();
    }

    public function test_legacy_public_photo_is_sanitized_once_without_reusing_private_verification_evidence(): void
    {
        Storage::fake('local'); Storage::fake('public');
        [$actor] = $this->actor();
        $source = $this->fixture(); $path = 'professional-photos/'.$actor->id.'/legacy.jpg';
        Storage::disk('public')->put($path,$source);
        $actor->forceFill(['public_professional_photo_path'=>$path])->save();
        $verification = 'account_verification/'.$actor->id.'/private.jpg';
        Storage::disk('local')->put($verification,'synthetic-private-verification-evidence');
        $profile = $actor->accountVerificationProfile;
        $profile->documents()->create(['kind'=>'identity_document','path'=>$verification,'original_name'=>'identity.jpg','mime_type'=>'image/jpeg','size_bytes'=>39]);
        $response = $this->get('/api/advertisers/'.$actor->id.'/photo')->assertOk();
        $this->assertSafe($response->getContent());
        $this->assertSame('synthetic-private-verification-evidence',Storage::disk('local')->get($verification));
        $display = 'professional-display/v1/legacy/'.hash('sha256',$path).'.jpg';
        Storage::disk('local')->assertExists($display);
        $this->assertSame($response->getContent(),$this->get('/api/advertisers/'.$actor->id.'/photo')->assertOk()->streamedContent());
        $actor->forceFill(['account_status'=>'suspended'])->save();
        $this->get('/api/advertisers/'.$actor->id.'/photo')->assertNotFound();
        app(ProfessionalPhotoService::class)->remove($path);
        Storage::disk('local')->assertMissing($display);
        Storage::disk('public')->assertMissing($path);
        Storage::disk('local')->assertExists($verification);
    }

    public function test_cloud_legacy_conversion_has_three_requests_and_no_extra_read_of_just_written_bytes(): void
    {
        $this->cloud(); $original = $this->fixture(); $stored = null;
        Http::fake(function ($request) use ($original,&$stored) {
            if (str_contains($request->url(),'/public/')) return Http::response($original,200,['Content-Type'=>'image/jpeg']);
            if ($request->method()==='POST') { $stored=$request->body(); return Http::response('',200); }
            return Http::response($stored ?? '',$stored === null ? 404 : 200,['Content-Type'=>'image/jpeg']);
        });
        $service = app(ProfessionalPhotoService::class);
        $response = $service->response('professional-photos/synthetic/legacy.jpg');
        $this->assertSafe($response->getContent());
        $this->assertSame($stored,$response->getContent());
        Http::assertSentCount(3);
        $this->assertSame($stored,$service->response('professional-photos/synthetic/legacy.jpg')->getContent());
        Http::assertSentCount(4);
        Http::assertNotSent(fn ($r)=>str_contains($r->url(),'account_verification'));
    }

    public function test_denied_cloud_derivative_never_falls_back_to_the_raw_upload(): void
    {
        $this->cloud(); Http::fake(['https://synthetic-storage.example/*'=>Http::response('',403)]);
        try {
            app(ProfessionalPhotoService::class)->response('professional-photos/synthetic/legacy.jpg');
            $this->fail('Denied derivative must not reveal an original.');
        } catch (\RuntimeException $error) { $this->assertStringContainsString('403',$error->getMessage()); }
        Http::assertSentCount(1);
        Http::assertNotSent(fn ($r)=>str_contains($r->url(),'/public/'));
    }

    private function actor(): array
    {
        $actor = User::create(['name'=>'Synthetic avatar owner','email'=>'avatar-privacy@example.test','password'=>'unusable',
            'account_type'=>'broker','phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $actor->roles()->sync([Role::where('key','registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        AccountVerificationProfile::create(['user_id'=>$actor->id,'type'=>'broker','status'=>'approved','submitted_at'=>now(),'reviewed_at'=>now(),'details'=>[]]);
        return [$actor,app(ApiTokenService::class)->issue($actor,request())['plain_text_token']];
    }

    private function cloud(): void
    {
        config(['services.supabase_storage.enabled'=>true,'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private','services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
    }

    private function assertSafe(string $bytes): void
    {
        $info = getimagesizefromstring($bytes);
        $this->assertSame('image/jpeg',$info['mime']);
        $this->assertLessThanOrEqual(640,max($info[0],$info[1]));
        $this->assertGreaterThan($info[0],$info[1]);
        $this->assertStringNotContainsString('Exif',$bytes);
        $this->assertStringNotContainsString('SYNTHETIC_CAMERA',$bytes);
    }

    private function fixture(): string
    {
        $image = imagecreatetruecolor(1200,600); imagefill($image,0,0,imagecolorallocate($image,20,90,160));
        ob_start(); imagejpeg($image,null,94); $jpeg=ob_get_clean(); imagedestroy($image);
        $make="SYNTHETIC_CAMERA\0";
        $tiff='II'.pack('vV',42,8).pack('v',3)
            .pack('vvVv',0x112,3,1,6)."\0\0"
            .pack('vvVV',0x10f,2,strlen($make),50)
            .pack('vvVV',0x8825,4,1,50+strlen($make)).pack('V',0).$make
            .pack('v',1).pack('vvV',1,2,2)."N\0\0\0".pack('V',0);
        $exif="Exif\0\0".$tiff;
        return substr($jpeg,0,2)."\xff\xe1".pack('n',strlen($exif)+2).$exif.substr($jpeg,2);
    }
}
