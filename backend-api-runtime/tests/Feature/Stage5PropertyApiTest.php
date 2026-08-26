<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class Stage5PropertyApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    public function test_complete_listing_lifecycle_with_images_under_stage6_identity(): void
    {
        [$user,$headers]=$this->verifiedUser();
        $created=$this->withHeaders($headers)->post('/api/properties',$this->listingPayload([
            'images'=>[
                UploadedFile::fake()->image('front.jpg',800,600),
                UploadedFile::fake()->image('inside.png',800,600),
            ],
        ]));
        $created->assertCreated()->assertJsonPath('data.status','draft')->assertJsonPath('data.review_status','draft')->assertJsonCount(2,'data.images');
        $id=(int)$created->json('data.id');
        $property=Property::query()->findOrFail($id);
        $this->assertSame($user->id,$property->user_id);
        $this->assertNull($property->owner_key);

        $paths=$property->images()->pluck('path')->all();
        foreach ($paths as $path) Storage::disk('public')->assertExists($path);

        $this->withHeaders(['Authorization'=>''])->getJson("/api/properties/$id")->assertNotFound();
        $this->withHeaders($headers)->getJson("/api/properties/$id")->assertOk()->assertJsonPath('data.is_owner',true);

        [, $other]=$this->verifiedUser('other-stage5@example.test','+967700000112');
        $this->withHeaders($other)->postJson("/api/properties/$id",['title'=>'Forbidden'])->assertForbidden();

        $updated=$this->withHeaders($headers)->post("/api/properties/$id",[
            'title'=>'Updated listing','replace_images'=>'1',
        ],['Accept'=>'application/json']);
        $updated->assertOk()->assertJsonPath('data.title','Updated listing')->assertJsonCount(0,'data.images');
        foreach ($paths as $path) Storage::disk('public')->assertMissing($path);

        $this->withHeaders($headers)->getJson('/api/properties/mine/list?per_page=10')
            ->assertOk()->assertJsonPath('meta.total',1)->assertJsonPath('data.0.id',$id);

        $this->withHeaders($headers)->deleteJson("/api/properties/$id")->assertOk();
        $this->assertDatabaseMissing('properties',['id'=>$id]);
        $this->assertDatabaseCount('property_images',0);
    }

    public function test_nearby_filters_bounds_and_orders_by_distance(): void
    {
        [, $headers]=$this->verifiedUser();
        $near=$this->createListing($headers,[
            'title'=>'Near property','latitude'=>'15.3694000','longitude'=>'44.1910000','price'=>'50000000',
        ]);
        $far=$this->createListing($headers,[
            'title'=>'Far property','latitude'=>'15.4200000','longitude'=>'44.2400000','price'=>'70000000',
        ]);

        $this->withHeaders(['Authorization'=>''])->getJson('/api/properties/nearby?latitude=15.3694&longitude=44.1910&radius_km=30&purpose=rent&min_price=40000000&south=15.30&west=44.10&north=15.50&east=44.30')
            ->assertOk()->assertJsonCount(2,'data')->assertJsonPath('data.0.id',$near)->assertJsonPath('data.1.id',$far);

        $this->withHeaders(['Authorization'=>''])->getJson('/api/properties/nearby?latitude=15.3694&longitude=44.1910&south=15.0')->assertUnprocessable();
    }

    public function test_private_listing_and_media_are_visible_only_to_authenticated_owner(): void
    {
        [, $headers]=$this->verifiedUser();
        $created=$this->withHeaders($headers)->post('/api/properties',$this->listingPayload([
            'images'=>[UploadedFile::fake()->image('private.jpg')],
        ]));
        $id=(int)$created->json('data.id');
        $imageId=(int)$created->json('data.images.0.id');
        Property::query()->whereKey($id)->update(['status'=>'pending']);

        $this->withHeaders(['Authorization'=>''])->getJson("/api/properties/$id")->assertNotFound();
        $this->withHeaders(['Authorization'=>''])->get("/api/property-media/$imageId")->assertNotFound();
        $this->withHeaders($headers)->getJson("/api/properties/$id")->assertOk();
        $this->withHeaders($headers)->get("/api/property-media/$imageId")->assertOk();
    }

    public function test_validation_rejects_more_than_twelve_total_images(): void
    {
        [, $headers]=$this->verifiedUser();
        $images=[];
        for ($i=0;$i<12;$i++) $images[]=UploadedFile::fake()->image("image-$i.jpg");
        $created=$this->withHeaders($headers)->post('/api/properties',$this->listingPayload(['images'=>$images]));
        $id=(int)$created->json('data.id');
        $this->withHeaders($headers)->post("/api/properties/$id",[
            'images'=>[UploadedFile::fake()->image('thirteenth.jpg')],
        ],['Accept'=>'application/json'])->assertUnprocessable()->assertJsonValidationErrors('images');
    }

    private function createListing(array $headers,array $overrides): int
    {
        $response=$this->withHeaders($headers)->post('/api/properties',$this->listingPayload($overrides));
        $response->assertCreated();
        $id=(int)$response->json('data.id');
        Property::query()->whereKey($id)->update(['status'=>'published','review_status'=>'approved']);
        return $id;
    }

    private function verifiedUser(
        string $email='stage5-regression@example.test',
        string $phone='+967700000111',
    ): array {
        $user=User::query()->create([
            'name'=>'Stage 5 Regression Owner','email'=>$email,'phone'=>$phone,
            'phone_verified_at'=>now(),'account_status'=>User::STATUS_ACTIVE,
            'password'=>Hash::make('StrongPass123!'),
        ]);
        $plain='re6_'.substr(hash('sha512',$email),0,80);
        $user->apiTokens()->create([
            'name'=>'test','token_hash'=>hash('sha256',$plain),
            'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour(),
        ]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function listingPayload(array $overrides=[]): array
    {
        return array_merge([
            'title'=>'Stage 5 regression property','description'=>'Full regression description',
            'purpose'=>'rent','type'=>'house','price'=>'50000000','currency'=>'YER',
            'area_m2'=>'220','bedrooms'=>'4','bathrooms'=>'3','address'=>'Sanaa',
            'latitude'=>'15.3694000','longitude'=>'44.1910000',
            'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ],$overrides);
    }
}
