"""Bounded synthetic transcode and real container SIGKILL. Never accesses UAT."""
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

IMAGE = 'aqer-video-worker:ci'
LIMITS = ['--network', 'none', '--cpus', '1', '--memory', '512m', '--pids-limit', '128',
          '--read-only', '--tmpfs', '/tmp:rw,nosuid,size=320m',
          '--tmpfs', '/var/www/html/storage:rw,uid=33,gid=33,mode=0700,size=16m']
PHP = r'''<?php
require '/var/www/html/vendor/autoload.php';
$app=require '/var/www/html/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$start=hrtime(true);
$out=app(\App\Services\ListingVideoTranscoder::class)->transcode('/tmp/input.mp4','/tmp');
$usage=getrusage(1);
$cpu=($usage['ru_utime.tv_sec']??0)+($usage['ru_utime.tv_usec']??0)/1e6
    +($usage['ru_stime.tv_sec']??0)+($usage['ru_stime.tv_usec']??0)/1e6;
echo 'AQER_VIDEO_BENCH '.json_encode(['transcode_ms'=>(hrtime(true)-$start)/1e6,
    'child_cpu_seconds'=>$cpu,'max_child_rss_kib'=>$usage['ru_maxrss']??null,
    'input_bytes'=>filesize('/tmp/input.mp4'),'playback_bytes'=>filesize($out['playback_file']),
    'poster_bytes'=>filesize($out['poster_file']),'width'=>$out['width'],'height'=>$out['height'],
    'duration_ms'=>$out['duration_ms']])."\n";
'''


def run(command, check=True, timeout=90):
    result=subprocess.run(command,capture_output=True,text=True,timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'synthetic video container command failed ({result.returncode})')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    rows=[]
    with tempfile.TemporaryDirectory(prefix='aqer-video-container-') as temp:
        probe=Path(temp)/'probe.php';probe.write_text(PHP);probe.chmod(0o644)
        # Image runs as www-data. Only this fixed public synthetic script is mounted.
        command=['docker','run','--rm',*LIMITS,'-e','APP_ENV=testing',
            '-e','LOG_CHANNEL=stderr','-e','VIDEO_WORKER_HEARTBEAT_ENABLED=false',
            '-v',str(probe)+':/probe.php:ro','--entrypoint','sh',IMAGE,'-eu','-c',
            'ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=12 '
            '-t 2 -c:v libx264 -threads 1 -filter_threads 1 -preset ultrafast -pix_fmt yuv420p /tmp/input.mp4 && php /probe.php']
        for _ in range(2):
            result=run(command)
            line=next((line for line in result.stdout.splitlines() if line.startswith('AQER_VIDEO_BENCH ')),None)
            if line is None: raise RuntimeError('video benchmark receipt absent')
            row=json.loads(line.removeprefix('AQER_VIDEO_BENCH '))
            assert row['width']==1280 and row['height']==720 and row['duration_ms']==2000
            assert row['playback_bytes']>0 and row['poster_bytes']>0
            rows.append(row)
        name='aqer-video-kill-'+secrets.token_hex(6)
        try:
            run(['docker','run','-d','--name',name,*LIMITS,'--entrypoint','ffmpeg',IMAGE,
                '-nostdin','-hide_banner','-loglevel','error','-re','-f','lavfi','-i',
                'testsrc2=size=1920x1080:rate=12','-t','90','-c:v','libx264','-threads','1',
                '-filter_threads','1','-preset','veryfast','-pix_fmt','yuv420p','/tmp/cancelled.mp4'])
            deadline=time.monotonic()+20
            while run(['docker','exec',name,'test','-s','/tmp/cancelled.mp4'],False).returncode:
                if time.monotonic()>deadline: raise RuntimeError('synthetic FFmpeg did not start')
                time.sleep(.1)
            run(['docker','kill','--signal','KILL',name])
            exit_code=int(run(['docker','wait',name]).stdout.strip())
            assert exit_code==137
        finally:
            run(['docker','rm','-f',name],False)
        # A new isolated consumer process can transcode after the real kill.
        recovered=run(command)
        assert 'AQER_VIDEO_BENCH ' in recovered.stdout
    report={'synthetic_only':True,'uat_accessed':False,'network':'none',
        'limits':{'cpu':1,'memory_mib':512,'pids':128,'tmpfs_mib':320},
        'samples':rows,'ffmpeg_container_sigkill_exit_code':exit_code,
        'new_container_transcode_after_kill':True,'actual_queue_lease_kill_tested':False,
        'physical_android_playback_tested':False,'commercial_capacity_proven':False}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('AQER_VIDEO_CONTAINER_PROBE '+json.dumps(report,sort_keys=True))


if __name__=='__main__': main()
