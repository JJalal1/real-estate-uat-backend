<?php

// Disposable CI only. This is not an artisan command or a deploy-time seeder.
if (getenv('GITHUB_ACTIONS') !== 'true' || getenv('AQER_CAPACITY_DISPOSABLE') !== '20261025'
    || getenv('APP_ENV') !== 'testing' || getenv('DB_DATABASE') !== 'aqer_capacity'
    || getenv('DB_HOST') !== '127.0.0.1' || getenv('DB_URL')) {
    fwrite(STDERR, "Disposable capacity preflight rejected.\n"); exit(1);
}
require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$db = \Illuminate\Support\Facades\DB::connection();
if (! $app->environment('testing') || $db->getDriverName() !== 'pgsql'
    || $db->getDatabaseName() !== 'aqer_capacity' || $db->getConfig('host') !== '127.0.0.1'
    || $db->table('users')->exists() || $db->table('properties')->exists()) {
    fwrite(STDERR, "Capacity database is not empty and disposable.\n"); exit(1);
}
$now = now()->format('Y-m-d H:i:s');
$users = [];
for ($i = 0; $i < 50; $i++) $users[] = ['name'=>'Synthetic capacity '.$i,
    'email'=>'capacity-'.$i.'@example.invalid','password'=>'no-login-capacity-fixture',
    'account_status'=>'active','phone_verified_at'=>$now,'profile_completed_at'=>$now,
    'created_at'=>$now,'updated_at'=>$now];
$db->table('users')->insert($users);
$owners = $db->table('users')->orderBy('id')->pluck('id')->all();
for ($offset = 0; $offset < 10000; $offset += 500) {
    $rows = [];
    for ($i = $offset; $i < $offset + 500; $i++) $rows[] = [
        'user_id'=>$owners[$i % 50],'title'=>'مكتب اصطناعي للسعة '.$i,
        'description'=>'بيانات CI اصطناعية فقط','purpose'=>$i % 2 ? 'rent' : 'sale',
        'type'=>'office','price'=>75000 + $i,'monthly_rent'=>$i % 2 ? 75000 : null,
        'currency'=>'YER','area_m2'=>65,'address'=>'إب حاضنة سعة اصطناعية',
        'latitude'=>15.123456 + intdiv($i,100)*.0002,'longitude'=>44.654321 + ($i % 100)*.0002,
        'status'=>'published','review_status'=>'approved','availability_status'=>'available',
        'published_at'=>$now,'created_at'=>$now,'updated_at'=>$now,
    ];
    $db->table('properties')->insert($rows);
}
$ids = $db->table('properties')->orderBy('id')->pluck('id')->all();
foreach (array_chunk($ids,500) as $chunk) {
    $rows = [];
    foreach ($chunk as $id) foreach ([0,1] as $n) $rows[] = ['property_id'=>$id,
        'path'=>'listing-originals/capacity/'.$id.'-'.$n.'.jpg','sort_order'=>$n,
        'is_primary'=>$n === 0,'created_at'=>$now,'updated_at'=>$now];
    $db->table('property_images')->insert($rows);
}
$db->statement('ANALYZE properties');
$db->statement('ANALYZE property_images');
$plan = $db->selectOne("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT id FROM properties WHERE status='published' AND location IS NOT NULL AND ST_DWithin(location,ST_SetSRID(ST_MakePoint(44.654321,15.123456),4326)::geography,100) ORDER BY id DESC LIMIT 20");
$report = ['scope'=>'Disposable PostgreSQL only; no UAT capacity claim',
    'properties'=>$db->table('properties')->count(),'owners'=>count($owners),
    'photo_metadata'=>$db->table('property_images')->count(),
    'cloud_storage_tested'=>false,'real_image_bytes_tested'=>false,
    'spatial_explain'=>json_decode($plan->{'QUERY PLAN'},true)];
file_put_contents(__DIR__.'/../../../capacity-fixture.json',json_encode($report,JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)."\n");
fwrite(STDOUT,"AQER_CAPACITY_FIXTURE ".json_encode(array_diff_key($report,['spatial_explain'=>true]))."\n");
