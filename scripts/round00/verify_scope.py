"""No product changes: this branch contains only the Round00 test harness."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = '03f77c1233776ef89868392b8afc0201a1dccdf5'
OUT = ROOT / 'round00-out'
OUT.mkdir(exist_ok=True)

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

components = ['mobile_app', 'backend-api-runtime', 'AGENTS.md', 'docs']
ids = {}
for component in components:
    original = git('rev-parse', SOURCE + ':' + component)
    current = git('rev-parse', 'HEAD:' + component)
    assert original == current, 'Product changed: ' + component
    ids[component] = original
changed = git('diff', '--name-only', SOURCE, 'HEAD').splitlines()
assert all(p.startswith('scripts/round00/') or p == '.github/workflows/round00-native-review.yml' for p in changed)
subprocess.run(['git','diff','--exit-code','--','mobile_app','backend-api-runtime'],cwd=ROOT,check=True,capture_output=True)
receipt = {'product_source': SOURCE, 'harness_source': git('rev-parse', 'HEAD'),
    'product_components_unchanged': ids, 'harness_only_changes': changed,
    'no_merge_or_deployment_or_cloud_mutation': True}
(OUT / 'SOURCE.json').write_text(json.dumps(receipt, indent=2) + '\n')
if '--apk' in sys.argv:
    apk = Path(os.environ['ROUND00_APK'])
    build_tools = sorted((Path(os.environ['ANDROID_HOME']) / 'build-tools').glob('*/apksigner'))[-1].parent
    signer = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    assert "name='com.aqer.yemen.uat'" in badging and "versionCode='1443'" in badging
    with zipfile.ZipFile(apk) as z:
        assert z.testzip() is None
        assert b'https://real-estate-uat-api-frankfurt.onrender.com/api' in z.read('lib/x86_64/libapp.so')
    receipt.update(apk_sha256=hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(), apk_bytes=apk.stat().st_size,
        apk_kind='Same-product-source x86_64 release rebuild for emulator only; not original UAT1443 bytes or signing certificate',
        original_uat1443_sha256='267665086cc694dce971edc2d355a6c2bd32dcecb55101821741538934708257',
        build_code=1443, apk_not_published=True)
    (OUT / 'APK.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (OUT / 'apk-signature-and-badging.txt').write_text(signer + '\n' + badging)
print(json.dumps(receipt))
