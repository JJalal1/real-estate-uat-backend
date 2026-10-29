#!/usr/bin/env python3
"""Prove W3-001/002 retain APK1393's original component implementation."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE='edb79f6436aa5fbb4c829f66c128c0f9a81b85b8'
TREE='dcf01a97907632e2d71f7d6460e04f547dc10f0f'
HOME='mobile_app/lib/features/discovery/presentation/marketplace_home_screen.dart'
ALLOWED={
 HOME,'mobile_app/lib/features/discovery/data/marketplace_repository.dart',
 'mobile_app/lib/features/discovery/data/marketplace_search_session.dart',
 'mobile_app/lib/features/discovery/presentation/home_ai_search_entry.dart',
 'mobile_app/lib/features/discovery/presentation/marketplace_search_panel.dart',
 'mobile_app/lib/features/discovery/presentation/marketplace_search_screen.dart',
 'mobile_app/lib/features/discovery/presentation/marketplace_section_screen.dart',
 'mobile_app/lib/router/app_router.dart',
}
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def blob(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def protected(path):
 return (path.startswith(('mobile_app/lib/','mobile_app/assets/','mobile_app/android/'))
   and path not in ALLOWED) or (path.startswith(('backend-api-runtime/app/','backend-api-runtime/resources/','backend-api-runtime/database/','backend-api-runtime/routes/'))
   and path!='backend-api-runtime/app/Http/Controllers/Api/PropertyController.php') or path=='mobile_app/pubspec.yaml'
def between(text,start,end):
 return text[text.index(start):text.index(end,text.index(start))].strip()
def main():
 p=argparse.ArgumentParser();p.add_argument('--baseline-ref',default=BASE);a=p.parse_args()
 assert git('rev-parse',a.baseline_ref+'^{tree}').decode().strip()==TREE,'Incorrect APK1393 tree'
 kept=0
 for entry in git('ls-tree','-rz',a.baseline_ref).split(b'\0'):
  if not entry:continue
  metadata,raw=entry.split(b'\t',1);mode,kind,sha=metadata.decode().split();path=raw.decode()
  if kind=='blob' and protected(path):
   target=ROOT/path
   assert target.is_file() and blob(target.read_bytes())==sha,'APK1393 component changed: '+path
   kept+=1
 for f in (ROOT/'mobile_app/lib').rglob('*'):
  if f.is_file():
   rel=f.relative_to(ROOT).as_posix()
   if rel not in ALLOWED:
    assert git('ls-tree',a.baseline_ref,'--',rel).strip(),'Unapproved new presentation component: '+rel
 old=git('show',a.baseline_ref+':'+HOME).decode();now=(ROOT/HOME).read_text()
 assert between(old,'  Widget _property(','\n/// A foreground')==between(now,'  Widget _property(','\n/// A foreground'),'Feed/card layout differs from APK1393'
 assert between(old,'SliverToBoxAdapter(child: SizedBox(height: 48','if (feed.hasValue')==between(now,'SliverToBoxAdapter(child: SizedBox(height: 48','if (feed.hasValue'),'Category layout differs from APK1393'
 assert old[old.index('\n/// A foreground'):].strip()==between(now,'\n/// A foreground','\nclass _HomeCircleAction'),'Broker/location component differs from APK1393'
 assert not (ROOT/'mobile_app/lib/core/widgets/ebroker_home').exists(),'Rejected W3-003 component directory is present'
 assert not (ROOT/'scripts/transplant_wave3_home.py').exists(),'Rejected W3-003 source transplant is present'
 print(json.dumps({'baseline_source':BASE,'baseline_tree':TREE,'owner_apk_version':1393,'preserved_component_blobs':kept,'category_feed_broker_bodies':'identical','W3-001':True,'W3-002':True,'W3-003':False,'verified':True}))
if __name__=='__main__':main()
