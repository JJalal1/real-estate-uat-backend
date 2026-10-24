<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\ListingImageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AdaptiveImageQualityTest extends TestCase
{
    use RefreshDatabase;

    public function test_derivatives_have_bounded_dimensions_and_measurably_smaller_payloads(): void
    {
        Storage::fake('local');
        $service=app(ListingImageService::class);
        $path=$service->store(UploadedFile::fake()->createWithContent('synthetic.jpg',$this->fixture()),'listing-originals/adaptive');
        $sizes=[];
        foreach (config('listing_media.variants') as $variant=>[$edge]) {
            $bytes=Storage::disk('local')->get($service->variantPath($path,$variant));
            $info=getimagesizefromstring($bytes);
            $this->assertSame('image/jpeg',$info['mime']);
            $this->assertLessThanOrEqual($edge,max($info[0],$info[1]));
            $this->assertStringNotContainsString('Exif',substr($bytes,0,2048));
            $sizes[$variant]=strlen($bytes);
        }
        $this->assertLessThan($sizes['card']*.6,$sizes['thumb']);
        $this->assertLessThan($sizes['gallery']*.5,$sizes['card']);
        $this->assertLessThan($sizes['gallery']*.75,$sizes['preview']);
        fwrite(STDOUT,"\nAQER_SYNTHETIC_IMAGE_BYTES ".json_encode($sizes)."\n");
    }

    public function test_historical_original_generates_only_the_requested_safe_variant(): void
    {
        Storage::fake('local');$path='listing-originals/adaptive/legacy.jpg';
        Storage::disk('local')->put($path,$this->fixture());$service=app(ListingImageService::class);
        $service->response($path,'thumb');
        Storage::disk('local')->assertExists($service->variantPath($path,'thumb'));
        foreach (['card','preview','detail','gallery','zoom'] as $variant) {
            Storage::disk('local')->assertMissing($service->variantPath($path,$variant));
        }
    }

    public function test_conditional_reuse_cannot_bypass_visibility_and_variant_reads_preserve_image_order(): void
    {
        Storage::fake('local');$service=app(ListingImageService::class);
        $path=$service->store(UploadedFile::fake()->createWithContent('synthetic.jpg',$this->fixture()),'listing-originals/adaptive');
        $user=User::create(['name'=>'Synthetic image fixture','email'=>'adaptive@example.test','password'=>'fixture-only']);
        $property=Property::create(['user_id'=>$user->id,'title'=>'Synthetic image quality test','type'=>'shop','purpose'=>'rent',
            'price'=>100,'currency'=>'YER','latitude'=>13.96,'longitude'=>44.18,'status'=>'published','review_status'=>'approved']);
        $first=$property->images()->create(['path'=>$path,'sort_order'=>0,'is_primary'=>true]);
        $second=$property->images()->create(['path'=>$path,'sort_order'=>1,'is_primary'=>false]);
        $url='/api/property-media/'.$first->id.'?variant=thumb';
        $response=$this->get($url)->assertOk()->assertHeader('Content-Type','image/jpeg')->assertHeader('X-Aqer-Image-Variant','thumb');
        $etag=$response->headers->get('ETag');$this->assertNotEmpty($etag);
        $this->withHeader('If-None-Match',$etag)->get($url)->assertStatus(304);
        $this->withHeaders(['If-None-Match'=>''])->get('/api/property-media/'.$second->id.'?variant=preview')->assertOk();
        $this->assertSame([$first->id,$second->id],$property->images()->orderBy('sort_order')->pluck('id')->all());
        $this->assertDatabaseCount('property_images',2);
        $property->status='draft';$property->save();
        $this->withHeader('If-None-Match',$etag)->get($url)->assertNotFound();
        $private=$service->response($path,'card',false);
        $this->assertStringContainsString('no-store',$private->headers->get('Cache-Control'));
        $this->assertFalse($private->headers->has('ETag'));
        $this->expectException(\Symfony\Component\HttpKernel\Exception\HttpException::class);
        $service->response($path,'original',false);
    }

    public function test_cached_cloud_derivative_downloads_once_and_conditional_reuse_never_reads_storage(): void
    {
        config(['services.supabase_storage.enabled'=>true,
            'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private',
            'services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
        $bytes = $this->fixture();
        Http::fake(['https://synthetic-storage.example/*'=>Http::response($bytes, 200, ['Content-Type'=>'image/jpeg'])]);
        $service = app(ListingImageService::class);
        $response = $service->response('listing-originals/synthetic.jpg', 'thumb', true);
        $this->assertSame($bytes, $response->getContent());
        Http::assertSentCount(1);
        Http::assertSent(fn ($request) => $request->method()==='GET' && str_contains($request->url(), '/private/listing-display/'));
        $this->assertSame('thumb', $response->headers->get('X-Aqer-Image-Variant'));
        request()->headers->set('If-None-Match', $response->headers->get('ETag'));
        $this->assertSame(304, $service->response('listing-originals/synthetic.jpg', 'thumb', true)->getStatusCode());
        Http::assertSentCount(1);
        request()->headers->remove('If-None-Match');
    }

    public function test_cloud_missing_derivative_is_sanitized_once_then_downloaded(): void
    {
        config(['services.supabase_storage.enabled'=>true,
            'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private',
            'services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
        $original = $this->fixture(); $stored = null;
        Http::fake(function ($request) use ($original, &$stored) {
            if (str_contains($request->url(), 'listing-originals')) return Http::response($original, 200);
            if ($request->method()==='POST') { $stored=$request->body(); return Http::response('', 200); }
            return Http::response($stored ?? '', $stored === null ? 404 : 200, ['Content-Type'=>'image/jpeg']);
        });
        $response = app(ListingImageService::class)->response('listing-originals/synthetic.jpg', 'thumb', false);
        Http::assertSentCount(4); // missing display, original, encoded write, encoded download.
        $info = getimagesizefromstring($response->getContent());
        $this->assertSame('image/jpeg', $info['mime']);
        $this->assertLessThanOrEqual(320, max($info[0], $info[1]));
        $this->assertNotSame($original, $response->getContent());
        $this->assertStringContainsString('no-store', $response->headers->get('Cache-Control'));
    }

    public function test_cloud_derivative_failure_never_silently_generates_or_returns_an_original(): void
    {
        config(['services.supabase_storage.enabled'=>true,
            'services.supabase_storage.url'=>'https://synthetic-storage.example',
            'services.supabase_storage.bucket'=>'synthetic-private',
            'services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
        Http::fake(['https://synthetic-storage.example/*'=>Http::response('', 403)]);
        try {
            app(ListingImageService::class)->response('listing-originals/synthetic.jpg', 'thumb', false);
            $this->fail('Denied storage must remain an error.');
        } catch (\RuntimeException $error) {
            $this->assertStringContainsString('403', $error->getMessage());
        }
        Http::assertSentCount(1);
        Http::assertNotSent(fn ($request) => $request->method()!=='GET' || str_contains($request->url(), 'listing-originals'));
    }

    private function fixture(): string
    {
        $image=imagecreatetruecolor(2400,1600);
        for ($y=0;$y<1600;$y+=8) for ($x=0;$x<2400;$x+=8) {
            $v=($x*7919+$y*104729)%16777216;
            imagefilledrectangle($image,$x,$y,$x+7,$y+7,$v);
        }
        ob_start();imagejpeg($image,null,94);$bytes=ob_get_clean();imagedestroy($image);
        return $bytes;
    }
}
