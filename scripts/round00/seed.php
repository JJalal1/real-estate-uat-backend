<?php
// Only a new local CI database. No cloud configuration or user account login.
if (getenv('GITHUB_ACTIONS') !== 'true' || getenv('AQER_ROUND00_DISPOSABLE') !== '20261030'
    || getenv('APP_ENV') !== 'testing' || getenv('DB_DATABASE') !== 'aqer_round00'
    || getenv('DB_HOST') !== '127.0.0.1' || getenv('DB_URL')) exit(41);
$root = dirname(__DIR__, 2);
require $root.'/backend-api-runtime/vendor/autoload.php';
$app = require $root.'/backend-api-runtime/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$db = \Illuminate\Support\Facades\DB::connection();
if ($db->getDatabaseName() !== 'aqer_round00' || $db->table('users')->exists()
    || $db->table('properties')->exists() || app(\App\Services\CloudAssetStorageService::class)->cloudEnabled()) exit(42);
$owner = \App\Models\User::factory()->create(['name'=>'مالك محاكاة اصطناعي',
    'email'=>'round00-owner@example.invalid', 'account_status'=>'active',
    'phone_verified_at'=>now(), 'profile_completed_at'=>now()]);
$imageService = app(\App\Services\ListingImageService::class);
$rows = [];
for ($i = 1; $i <= 36; $i++) {
    $rent = $i % 2 === 0;
    $type = ['apartment','house','villa','shop'][$i % 4];
    $property = \App\Models\Property::create(['user_id'=>$owner->id,
        'title'=>'عقار اختبار محاكاة '.str_pad((string)$i,2,'0',STR_PAD_LEFT),
        'description'=>'بيانات وصور اصطناعية حصرًا لفحص Android. لا يمثل هذا العقار عرضًا حقيقيًا.',
        'type'=>$type,'purpose'=>$rent?'rent':'sale', 'price'=>$rent?150000:30000000,
        'monthly_rent'=>$rent?150000:null,'currency'=>'YER','area_m2'=>180,'bedrooms'=>3,'bathrooms'=>2,
        'address'=>'صنعاء، حدة، منطقة اختبار محاكاة','latitude'=>15.3694+($i%6)*.001,
        'longitude'=>44.1910+intdiv($i,6)*.001,'status'=>'published','review_status'=>'approved',
        'published_at'=>now()->subMinutes($i)]);
    $property->forceFill(['availability_status'=>'available'])->save();
    $image = imagecreatetruecolor(1200,900);
    imagefill($image,0,0,imagecolorallocate($image,70+($i*7)%110,150+($i*3)%80,205));
    imagefilledrectangle($image,180,150,1020,880,imagecolorallocate($image,235,215,180));
    for ($r=0;$r<4;$r++) for ($c=0;$c<4;$c++)
        imagefilledrectangle($image,230+$c*190,210+$r*150,330+$c*190,310+$r*150,imagecolorallocate($image,25,65,88));
    imagestring($image,5,25,30,'ROUND00 SYNTHETIC IMAGE '.$i,imagecolorallocate($image,15,35,55));
    $temp = tempnam(sys_get_temp_dir(),'round00-image-');imagejpeg($image,$temp,92);imagedestroy($image);
    $upload = new \Illuminate\Http\UploadedFile($temp,'synthetic-'.$i.'.jpg','image/jpeg',null,true);
    $path = $imageService->store($upload,'listing-originals/round00');unlink($temp);
    $photo = $property->images()->create(['path'=>$path,'sort_order'=>0,'is_primary'=>true]);
    $rows[] = ['id'=>$property->id,'image_id'=>$photo->id,'title'=>$property->title,'purpose'=>$property->purpose];
}
file_put_contents($root.'/round00-out/FIXTURE.json',json_encode(['kind'=>'CI-only synthetic data and actual generated image bytes',
    'database'=>'aqer_round00','cloud_storage'=>false,'properties'=>$rows,'users'=>1,'remote_writes'=>false],JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE)."\n");
echo "ROUND00_SYNTHETIC_FIXTURE_READY ".count($rows)."\n";
