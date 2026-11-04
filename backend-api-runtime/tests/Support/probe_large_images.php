<?php

// Disposable CI only: no database, provider credentials or UAT traffic.
require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['services.supabase_storage.enabled'=>false, 'listing_media.watermark.enabled'=>false]);

$root = sys_get_temp_dir().'/aqer-large-images';
if (! is_dir($root)) mkdir($root, 0700, true);
if (($argv[1] ?? '') === 'worker') {
    $index = (int) $argv[2]; $orientation = (int) $argv[3];
    $source = $root.'/source-'.$orientation.'.jpg';
    while (! is_file($root.'/start')) usleep(10000);
    $start = hrtime(true);
    $service = app(\App\Services\ListingImageService::class);
    $busy=0;
    while (true) {
        try {
            $path = $service->store(new \Illuminate\Http\UploadedFile($source, '24mp.jpg', 'image/jpeg', null, true), 'listing-originals/benchmark', 'worker-'.$index);
            break;
        } catch (\Symfony\Component\HttpKernel\Exception\HttpException $error) {
            if ($error->getStatusCode()!==503 || ++$busy>15 || ($error->getHeaders()['Retry-After'] ?? null)!=='2') throw $error;
            usleep(2050000+$index*10000);
        }
    }
    $variants = [];
    foreach (config('listing_media.variants') as $variant=>[$edge]) {
        $bytes = \Illuminate\Support\Facades\Storage::disk('local')->get($service->variantPath($path, $variant));
        $info = getimagesizefromstring($bytes);
        if ($info['mime'] !== 'image/jpeg' || max($info[0], $info[1]) > $edge || str_contains(substr($bytes,0,2048), 'Exif')) throw new \RuntimeException('Unsafe derivative');
        if (($orientation === 6) !== ($info[1] > $info[0])) throw new \RuntimeException('Orientation was not preserved');
        $variants[$variant] = ['bytes'=>strlen($bytes),'width'=>$info[0],'height'=>$info[1]];
    }
    echo json_encode(['worker'=>$index, 'orientation'=>$orientation, 'busy_retries'=>$busy, 'elapsed_ms'=>(hrtime(true)-$start)/1e6,
        'peak_rss_kib'=>getrusage()['ru_maxrss'], 'php_peak_bytes'=>memory_get_peak_usage(true), 'source_bytes'=>filesize($source), 'variants'=>$variants], JSON_THROW_ON_ERROR)."\n";
    exit;
}

// Exactly 24,000,000 pixels, detailed synthetic pattern, no human media.
$image = imagecreatetruecolor(6000, 4000);
for ($y=0; $y<4000; $y+=12) for ($x=0; $x<6000; $x+=12) {
    imagefilledrectangle($image,$x,$y,$x+11,$y+11,($x*7919+$y*104729)%16777216);
}
ob_start(); imagejpeg($image,null,90); $bytes=ob_get_clean(); imagedestroy($image); unset($image);
file_put_contents($root.'/source-1.jpg',$bytes);
$exif="Exif\0\0"."II\x2a\0\x08\0\0\0"."\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0";
file_put_contents($root.'/source-6.jpg',substr($bytes,0,2)."\xff\xe1".pack('n',strlen($exif)+2).$exif.substr($bytes,2));
if (strlen($bytes)>8*1024*1024) throw new \RuntimeException('Fixture exceeds accepted byte budget');
unset($bytes);
$runs=[]; $failed=false;
foreach ([1,2,3] as $concurrency) {
    @unlink($root.'/start'); $children=[]; $start=microtime(true); $rssMax=0;
    for ($i=0;$i<$concurrency;$i++) {
        $pipes=[];
        $process=proc_open([PHP_BINARY,'-d','memory_limit=256M',__FILE__,'worker',(string)$i,$i===0?'1':'6'],[1=>['pipe','w'],2=>['pipe','w']],$pipes);
        if (! is_resource($process)) throw new \RuntimeException('Cannot start worker');
        $children[]=['process'=>$process,'pipes'=>$pipes,'exit'=>null];
    }
    touch($root.'/start');
    do {
        $running=false; $rss=0;
        foreach ($children as &$child) {
            $status=proc_get_status($child['process']);
            if ($status['running']) {
                $running=true;
                $statusText=@file_get_contents('/proc/'.$status['pid'].'/status') ?: '';
                if (preg_match('/^VmRSS:\s+(\d+)/m',$statusText,$match)) $rss+=(int)$match[1];
            } elseif ($child['exit']===null) $child['exit']=$status['signaled'] ? 128+$status['termsig'] : $status['exitcode'];
        }
        unset($child); $rssMax=max($rssMax,$rss);
        if (microtime(true)-$start>120) throw new \RuntimeException('Image workload timed out');
        usleep(10000);
    } while ($running);
    $workers=[];
    foreach ($children as $child) {
        $out=stream_get_contents($child['pipes'][1]); $err=stream_get_contents($child['pipes'][2]);
        fclose($child['pipes'][1]);fclose($child['pipes'][2]);proc_close($child['process']);
        $row=json_decode(trim($out),true);
        $workers[]=['exit'=>$child['exit'],'result'=>$row,'stderr'=>$err];
        if ($child['exit']!==0 || !is_array($row)) $failed=true;
    }
    $runs[]=['concurrency'=>$concurrency,'wall_ms'=>(microtime(true)-$start)*1000,'sampled_sum_rss_kib'=>$rssMax,'workers'=>$workers];
}
$memoryFile='/sys/fs/cgroup/memory.peak';
$receipt=['pixels'=>24000000,'php_limit'=>'256M','container_limit_bytes'=>536870912,'cpu_limit'=>1,
    'cgroup_peak_bytes'=>is_file($memoryFile)?(int)file_get_contents($memoryFile):null,'runs'=>$runs,'passed'=>!$failed,
    'scope'=>'Exact GD runtime; local private disk, no cloud/network/Android capacity claim'];
file_put_contents('/tmp/large-images-result.json',json_encode($receipt,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES)."\n");
echo 'AQER_LARGE_IMAGES '.json_encode($receipt,JSON_UNESCAPED_SLASHES)."\n";
exit($failed?1:0);
