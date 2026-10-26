<?php

require __DIR__.'/../../vendor/autoload.php';
$app=require __DIR__.'/../../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (!app()->environment('testing')) exit(1);
$gate=app(\App\Services\ListingImageEncodingGate::class);
if (($argv[1]??'')==='worker') {
    if (posix_geteuid()===0) exit(1);
    $gate->run(fn () => print('WWW_ENCODER_LOCK_PASS'));
    exit;
}
if (posix_geteuid()!==0) exit(1);
// Only a fresh disposable CI container; no user media or live lock is touched.
$path=storage_path('framework/cache/listing-image-encoding.lock');
if (is_file($path)) unlink($path);
$gate->run(fn () => null);chmod($path,0644);
$inode=fileinode($path);
$process=new \Symfony\Component\Process\Process(['su','-s','/bin/sh','www-data','-c',
    escapeshellarg(PHP_BINARY).' '.escapeshellarg(__FILE__).' worker']);
$process->setTimeout(10);$process->mustRun();
if ($process->getOutput()!=='WWW_ENCODER_LOCK_PASS' || $inode!==fileinode($path)) exit(1);
echo "AQER_ENCODER_CLI_WEB_INODE_PASS\n";
