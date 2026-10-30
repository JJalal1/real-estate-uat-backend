"""Still execute verified APK if isolated network setup fails after Android boot."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

root=Path(__file__).resolve().parents[2];out=root/'round00-out'
if (out/'REVIEW.json').exists() or not (out/'APK.json').exists():raise SystemExit(0)
apk=Path(os.environ['RUNNER_TEMP'])/'round00-app.apk'
try:
    boot=subprocess.run(['adb','shell','getprop','sys.boot_completed'],capture_output=True,text=True,timeout=8)
    if boot.stdout.strip()!='1':raise SystemExit(0)
    expected=json.loads((out/'APK.json').read_text())['apk_sha256']
    assert hashlib.file_digest(apk.open('rb'),'sha256').hexdigest()==expected
    subprocess.run(['adb','root'],check=True,capture_output=True,timeout=10)
    subprocess.run(['adb','wait-for-device'],check=True,capture_output=True,timeout=10)
    subprocess.run(['adb','shell','iptables','-I','OUTPUT','-j','REJECT'],check=True,capture_output=True,timeout=10)
    subprocess.run(['adb','shell','iptables','-C','OUTPUT','-j','REJECT'],check=True,capture_output=True,timeout=10)
    subprocess.run(['adb','install','-r',str(apk)],check=True,capture_output=True,timeout=90)
    (out/'OFFLINE_FALLBACK.json').write_text(json.dumps({'all_guest_network_rejected':True,
        'reason':'Isolated environment step stopped before normal app navigation',
        'apk_sha256':expected,'not_a_live_or_backend_journey_acceptance':True},indent=2))
    env=os.environ.copy();env['ROUND00_OFFLINE_FALLBACK']='true'
    subprocess.run([sys.executable,str(root/'scripts/round00/native_review.py')],env=env,cwd=root,timeout=500,check=False)
except Exception as error:
    (out/'OFFLINE_FALLBACK_ERROR.txt').write_text(type(error).__name__+': '+str(error)[:400])
