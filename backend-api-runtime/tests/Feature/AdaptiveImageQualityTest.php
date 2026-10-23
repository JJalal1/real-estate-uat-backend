<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Services\ListingImageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
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
