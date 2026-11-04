'use strict';
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawn,spawnSync}=require('node:child_process');
const {EventEmitter}=require('node:events');
const {PassThrough}=require('node:stream');
const p=require('./index.js');
let fixtureRoot,cipher,fakeScript;
const SENTINEL='PRIVATE_TEST_SENTINEL_MUST_NOT_ENTER_LOGS';

before(async()=>{
  fixtureRoot=await fs.mkdtemp(path.join(os.tmpdir(),'aqer-action-test-'));
  await fs.chmod(fixtureRoot,0o700);
  const plain=path.join(fixtureRoot,'synthetic.txt');
  const key=path.join(fixtureRoot,'generated-test-key.pem');
  const cert=path.join(fixtureRoot,'generated-test-recipient.pem');
  await fs.writeFile(plain,'Synthetic checkpoint, no real account or task key.');
  let r=spawnSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,
    '-out',cert,'-days','1','-subj','/CN=OfflineActionTestOnly'],{stdio:'ignore'});
  assert.equal(r.status,0);
  const encoded=path.join(fixtureRoot,'synthetic.cms');
  r=spawnSync('openssl',['cms','-encrypt','-aes-256-cbc','-binary','-in',plain,
    '-outform','DER','-out',encoded,cert],{stdio:'ignore'});
  assert.equal(r.status,0);cipher=await fs.readFile(encoded);
  fakeScript=path.join(fixtureRoot,'fake-owner.js');
  await fs.writeFile(fakeScript,`
  'use strict';
  const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');
  const readline=require('node:readline');const root=process.argv[2];const cfg=JSON.parse(process.env.TEST_CONTEXT);
  const mode=process.env.TEST_MODE;let current=0;process.on('SIGTERM',()=>{});
  process.stderr.write('${SENTINEL}\\n');
  function ready(seq,kind){
    const d=path.join(root,'checkpoints',String(seq).padStart(6,'0'));fs.mkdirSync(d,{recursive:true,mode:0o700});
    fs.chmodSync(path.join(root,'checkpoints'),0o700);fs.chmodSync(d,0o700);
    const data=fs.readFileSync(process.env.TEST_CMS);fs.writeFileSync(path.join(d,'checkpoint.cms'),data,{mode:0o600});
    const receipt={version:1,repo:'${p.REPO}',run_id:cfg.runId,run_attempt:cfg.attempt,
      source_sha:cfg.source,toolbundle_sha:cfg.bundle,seq,kind,phase:kind==='terminal_checkpoint'?'C5':'C1',
      cursor:kind==='terminal_checkpoint'?'CLEANED':'FIXTURE',checkpoint_challenge:'c'.repeat(64),
      prev_result_sha:'0'.repeat(64),cipher_sha:crypto.createHash('sha256').update(data).digest('hex'),
      cipher_bytes:data.length,created_utc:'2026-11-04T01:02:03Z',phase1_accepted:false};
    fs.writeFileSync(path.join(d,'PUBLIC_RECEIPT.json'),JSON.stringify(receipt)+'\\n',{mode:0o600});
    process.stdout.write(JSON.stringify({event:'checkpoint_ready',seq,checkpoint_dir:'checkpoints/'+String(seq).padStart(6,'0')})+'\\n');
  }
  if(mode==='hang'){setInterval(()=>{},1000);}
  else if(mode==='leak'){process.stdout.write('${SENTINEL}\\n');setInterval(()=>{},1000);}
  else if(mode==='path'){process.stdout.write(JSON.stringify({event:'checkpoint_ready',seq:0,checkpoint_dir:'../private'})+'\\n');setInterval(()=>{},1000);}
  else if(mode==='long'){process.stdout.write('x'.repeat(2048));setInterval(()=>{},1000);}
  else{
    const rl=readline.createInterface({input:process.stdin});
    rl.on('line',line=>{
      const ack=JSON.parse(line);fs.appendFileSync(process.env.TEST_ACKS,JSON.stringify(ack)+'\\n');
      if(mode==='early_terminal'){process.exit(ack.success?0:7);}
      if(current===0){
        if(mode==='exit_without_terminal'){process.exit(0);}
        if(mode==='duplicate'){process.stdout.write(JSON.stringify({event:'checkpoint_ready',seq:0,checkpoint_dir:'checkpoints/000000'})+'\\n');return;}
        current=1;ready(mode==='late_terminal_gap'||mode==='late_review_gap'?3:1,mode==='late_review_gap'?'review_checkpoint':'terminal_checkpoint');
      }else process.exit(ack.success?0:7);
    });
    ready(mode==='early_terminal'||mode==='early_review'?1:0,mode==='early_terminal'?'terminal_checkpoint':mode==='early_review'?'review_checkpoint':'fixture_checkpoint');
    if(mode==='overlap')process.stdout.write(JSON.stringify({event:'checkpoint_ready',seq:1,checkpoint_dir:'checkpoints/000001'})+'\\n');
  }
  `);
});
after(async()=>{await fs.rm(fixtureRoot,{recursive:true,force:true});});

async function context(t){
  const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aqer-action-case-'));
  await fs.chmod(temp,0o700);t.after(()=>fs.rm(temp,{recursive:true,force:true}));
  const script=path.join(temp,'fixed-owner.py');await fs.writeFile(script,'# not executed\n');
  return {root:path.join(temp,'run-root'),script,runId:'9001',attempt:2,source:'a'.repeat(40),bundle:'b'.repeat(64),
    ownerMilliseconds:3000,cleanupMilliseconds:100};
}
async function checkpoint(cfg,seq=0,change={}){
  const d=path.join(cfg.root,'checkpoints',String(seq).padStart(6,'0'));
  await fs.mkdir(d,{recursive:true,mode:0o700});await fs.chmod(cfg.root,0o700);
  await fs.chmod(path.dirname(d),0o700);await fs.chmod(d,0o700);
  await fs.writeFile(path.join(d,'checkpoint.cms'),cipher,{mode:0o600});
  const receipt={version:1,repo:p.REPO,run_id:cfg.runId,run_attempt:cfg.attempt,
    source_sha:cfg.source,toolbundle_sha:cfg.bundle,seq,
    kind:seq===0?'fixture_checkpoint':'review_checkpoint',phase:'C1',cursor:'FIXTURE',
    checkpoint_challenge:'c'.repeat(64),prev_result_sha:'0'.repeat(64),
    cipher_sha:crypto.createHash('sha256').update(cipher).digest('hex'),cipher_bytes:cipher.length,
    created_utc:'2026-11-04T01:02:03Z',phase1_accepted:false,...change};
  await fs.writeFile(path.join(d,'PUBLIC_RECEIPT.json'),JSON.stringify(receipt),{mode:0o600});
  return {directory:d,receipt};
}
async function runFake(t,mode,upload=async()=>({id:123,digest:'d'.repeat(64)}),overrides={}){
  const cfg={...await context(t),...overrides};
  const cms=path.join(fixtureRoot,'synthetic.cms'),acks=path.join(path.dirname(cfg.root),'acks.jsonl');
  const logs=[],observed=[];
  const env={...process.env,ACTIONS_RUNTIME_TOKEN:'synthetic-action-token',ACTIONS_RESULTS_URL:'synthetic-url',
    ACTIONS_RUNTIME_URL:'synthetic-runtime',GITHUB_TOKEN:'synthetic-read-token'};
  const options={env,log:line=>logs.push(line),upload:async req=>{observed.push(req);return upload(req,observed.length);},
    killObservationMilliseconds:50,uploadMilliseconds:500,
    spawnOwner:(cmd,args,opts)=>{
      assert.equal(cmd,'python3');assert.equal(opts.env.ACTIONS_RUNTIME_TOKEN,undefined);
      assert.deepEqual(args,['-B',cfg.script,'--run-root',cfg.root]);
      assert.equal(opts.env.ACTIONS_RESULTS_URL,undefined);assert.equal(opts.env.ACTIONS_RUNTIME_URL,undefined);
      assert.equal(opts.env.GITHUB_TOKEN,'synthetic-read-token');
      return spawn(process.execPath,[fakeScript,cfg.root],{...opts,env:{...opts.env,
        TEST_MODE:mode,TEST_CMS:cms,TEST_CONTEXT:JSON.stringify(cfg),TEST_ACKS:acks}});
    }};
  return {cfg,logs,observed,acks,promise:p.supervise(cfg,options)};
}

test('flat JSON rejects duplicates, escapes, nesting and non-finite primitives',()=>{
  for(const raw of ['{"seq":1,"seq":2}','{"seq":1,"\\u0073eq":2}','{"nested":{}}',
    '{"a":[1]}','{"a":NaN}','{"a":1e999}','{} trailing']){
    assert.throws(()=>p.parseFlatJSON(Buffer.from(raw),1024));
  }
  assert.equal(p.parseFlatJSON(Buffer.from('{"valid":false,"seq":0}'),1024).seq,0);
});
test('parser exceptions never contain submitted private text',()=>{
  for(const raw of [Buffer.from('{"note":"'+SENTINEL+'\\q"}'),Buffer.from([0xff])]){
    assert.throws(()=>p.parseFlatJSON(raw,1024),error=>error instanceof p.Refused && !error.message.includes(SENTINEL));
  }
});
test('runtime env is stripped only from Python and read token is retained',()=>{
  const e=p.childEnvironment({ACTIONS_RUNTIME_TOKEN:'x',ACTIONS_ID_TOKEN_REQUEST_TOKEN:'x',
    ACTIONS_RESULTS_URL:'x',ACTIONS_RUNTIME_URL:'x',GITHUB_TOKEN:'read',AQER_PHASE1_TEST_ACCESS_JSON:'synthetic'});
  assert.deepEqual(e,{GITHUB_TOKEN:'read',AQER_PHASE1_TEST_ACCESS_JSON:'synthetic'});
});
test('CI configuration is fixed to reviewed repository and source',()=>{
  const env={GITHUB_ACTIONS:'true',GITHUB_REPOSITORY:p.REPO,GITHUB_RUN_ID:'9001',GITHUB_RUN_ATTEMPT:'2',
    GITHUB_SHA:'a'.repeat(40),AQER_BRIDGE_TOOLBUNDLE_SHA:'b'.repeat(64),RUNNER_TEMP:'/runner/temp',GITHUB_WORKSPACE:'/runner/work'};
  const cfg=p.configFromEnvironment(env);assert.equal(cfg.root,'/runner/temp/aqer-phase1-bridge-9001-2');
  assert.equal(p.OWNER_RELATIVE,'scripts/run_phase1_native_bridge.py');
  assert.equal(cfg.script,'/runner/work/scripts/run_phase1_native_bridge.py');assert.equal(cfg.ownerMilliseconds,6200000);
  for(const update of [{GITHUB_REPOSITORY:'foreign/repo'},{GITHUB_RUN_ATTEMPT:'0'},
    {GITHUB_SHA:'X'.repeat(40)},{'INPUT_OWNER-TIMEOUT-SECONDS':'7201'},
    {'INPUT_CLEANUP-GRACE-SECONDS':'181'}])assert.throws(()=>p.configFromEnvironment({...env,...update}));
});
test('valid CMS and receipt are staged as exactly two files with actual digest',async t=>{
  const cfg=await context(t);await checkpoint(cfg);
  const result=await p.prepareCheckpoint(cfg,0);assert.deepEqual((await fs.readdir(result.directory)).sort(),['PUBLIC_RECEIPT.json','checkpoint.cms']);
  assert.deepEqual(await fs.readFile(result.files[0]),cipher);
  assert.equal((await fs.stat(result.files[0])).mode&0o777,0o600);
  assert.equal(result.receipt.phase1_accepted,false);
});
test('wrong receipt identity, unknown keys, digest, size and UTC fail closed',async t=>{
  for(const mutation of [{run_id:'9002'},{source_sha:'f'.repeat(40)},{cipher_sha:'f'.repeat(64)},
    {cipher_bytes:1},{phase1_accepted:true},{unexpected:'PRIVATE_SENTINEL'},
    {created_utc:'2026-02-31T01:02:03Z'},{kind:'terminal_checkpoint'}]){
    const cfg=await context(t);await checkpoint(cfg,0,mutation);
    await assert.rejects(p.prepareCheckpoint(cfg,0));
  }
});
test('duplicate receipt keys cannot hide private content before upload',async t=>{
  const cfg=await context(t);const c=await checkpoint(cfg);
  const raw=JSON.stringify(c.receipt).replace('"phase1_accepted":false','"phase1_accepted":"PRIVATE_SENTINEL","phase1_accepted":false');
  await fs.writeFile(path.join(c.directory,'PUBLIC_RECEIPT.json'),raw);
  await assert.rejects(p.prepareCheckpoint(cfg,0),/json_duplicate_key/);
});
test('extra files and private raw evidence are never included',async t=>{
  const cfg=await context(t);const c=await checkpoint(cfg);
  await fs.writeFile(path.join(c.directory,'raw-auth.png'),'synthetic private test',{mode:0o600});
  await assert.rejects(p.prepareCheckpoint(cfg,0),/file_allowlist/);
});
test('plaintext renamed CMS and valid CMS with appended data are rejected',async t=>{
  for(const bytes of [Buffer.from('THIS IS PLAINTEXT'),Buffer.concat([cipher,Buffer.from('PRIVATE_TRAILING')])]){
    const cfg=await context(t);const c=await checkpoint(cfg);
    await fs.writeFile(path.join(c.directory,'checkpoint.cms'),bytes);
    await assert.rejects(p.prepareCheckpoint(cfg,0));
  }
});
test('symlink, hardlink and broad-mode checkpoint files are rejected',async t=>{
  for(const kind of ['symlink','hardlink','broad']){
    const cfg=await context(t);const c=await checkpoint(cfg);const target=path.join(c.directory,'checkpoint.cms');
    if(kind==='broad')await fs.chmod(target,0o644);
    else{await fs.unlink(target);const outside=path.join(path.dirname(cfg.root),'outside.cms');await fs.writeFile(outside,cipher,{mode:0o600});
      if(kind==='symlink')await fs.symlink(outside,target);else await fs.link(outside,target);}
    await assert.rejects(p.prepareCheckpoint(cfg,0));
  }
});
test('symlink checkpoint directory cannot redirect uploads',async t=>{
  const cfg=await context(t);const c=await checkpoint(cfg);
  const moved=path.join(cfg.root,'moved');await fs.rename(c.directory,moved);await fs.symlink(moved,c.directory);
  await assert.rejects(p.prepareCheckpoint(cfg,0),/symlink_refused/);
});
test('FIFO and nonregular checkpoint files are refused without blocking open',async t=>{
  const cfg=await context(t);const c=await checkpoint(cfg);const target=path.join(c.directory,'checkpoint.cms');
  await fs.unlink(target);assert.equal(spawnSync('mkfifo',[target],{stdio:'ignore'}).status,0);
  const began=Date.now();await assert.rejects(p.prepareCheckpoint(cfg,0),/private_regular_file_required/);
  assert.ok(Date.now()-began<1000);
});
test('successful owner uses unique artifacts and receives only real id/digest ACKs',async t=>{
  const run=await runFake(t,'success');const result=await run.promise;
  assert.equal(result.status,'owner_completed');assert.equal(result.checkpoints,2);
  assert.deepEqual(run.observed.map(r=>r.name),['aqer-bridge-9001-2-000000','aqer-bridge-9001-2-000001']);
  const acks=(await fs.readFile(run.acks,'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(acks.map(a=>a.success),[true,true]);assert.equal(acks[0].artifact_id,123);
  assert.equal(acks[0].digest,'d'.repeat(64));assert.ok(!run.logs.join('\n').includes(SENTINEL));
});
test('missing optional outer digest remains null rather than fabricated',async t=>{
  const run=await runFake(t,'success',async()=>({id:321}));await run.promise;
  const ack=JSON.parse((await fs.readFile(run.acks,'utf8')).trim().split('\n')[0]);assert.equal(ack.digest,null);
});
test('early terminal sequence one can preserve cleanup evidence before fixture allocation',async t=>{
  const run=await runFake(t,'early_terminal');const result=await run.promise;
  assert.equal(result.checkpoints,1);assert.equal(run.observed.length,1);
  assert.equal(run.observed[0].name,'aqer-bridge-9001-2-000001');
  const ack=JSON.parse((await fs.readFile(run.acks,'utf8')).trim());assert.equal(ack.success,true);assert.equal(ack.seq,1);
});
test('initial sequence one cannot bypass the required fixture checkpoint for a review',async t=>{
  const run=await runFake(t,'early_review');await assert.rejects(run.promise,/checkpoint_upload_failed/);
  assert.equal(run.observed.length,0);
});
test('terminal evidence may skip allocated but unannounced failed checkpoints',async t=>{
  const run=await runFake(t,'late_terminal_gap');const result=await run.promise;
  assert.equal(result.checkpoints,2);
  assert.deepEqual(run.observed.map(r=>r.name),['aqer-bridge-9001-2-000000','aqer-bridge-9001-2-000003']);
});
test('a forward sequence gap never authorizes a review checkpoint upload',async t=>{
  const run=await runFake(t,'late_review_gap');await assert.rejects(run.promise,/checkpoint_upload_failed/);
  assert.equal(run.observed.length,1);
});
test('failed upload sends one negative ACK and allows a fresh terminal cleanup checkpoint',async t=>{
  const run=await runFake(t,'success',async(_req,call)=>{if(call===1)throw Error(SENTINEL);return{id:222,digest:'d'.repeat(64)};});
  await assert.rejects(run.promise,/checkpoint_upload_failed/);
  assert.equal(run.observed.length,2);
  const acks=(await fs.readFile(run.acks,'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(acks.map(a=>a.success),[false,true]);assert.equal(acks[0].artifact_id,null);
  assert.ok(!run.logs.join('\n').includes(SENTINEL));
});
test('malformed private stdout, path escapes, oversized and duplicate messages never retry',async t=>{
  for(const mode of ['leak','path','long','duplicate','overlap']){
    const run=await runFake(t,mode);await assert.rejects(run.promise);
    assert.ok(!run.logs.join('\n').includes(SENTINEL));assert.ok(run.observed.length<=1);
  }
});
test('an exit code zero without terminal evidence is not completion',async t=>{
  const run=await runFake(t,'exit_without_terminal');await assert.rejects(run.promise,/terminal_checkpoint_missing/);
});
test('hung owner receives bounded termination and is never reported complete',async t=>{
  const began=Date.now();const run=await runFake(t,'hang',undefined,{ownerMilliseconds:40,cleanupMilliseconds:30});
  await assert.rejects(run.promise,/owner_timeout/);assert.ok(Date.now()-began<2000);
});
test('upload returning an invented receipt is refused without a second attempt',async t=>{
  const run=await runFake(t,'success',async()=>({id:0,digest:'not-a-digest'}));
  await assert.rejects(run.promise,/checkpoint_upload_failed/);assert.equal(run.observed.length,2);
});
test('an upload timeout is not retried and still permits fresh terminal evidence',async t=>{
  const cfg=await context(t), logs=[], calls=[];
  const acks=path.join(path.dirname(cfg.root),'timeout-acks');
  await assert.rejects(p.supervise(cfg,{env:{...process.env},log:x=>logs.push(x),uploadMilliseconds:20,
    spawnOwner:(_cmd,_args,opts)=>spawn(process.execPath,[fakeScript,cfg.root],{...opts,env:{...opts.env,
      TEST_MODE:'success',TEST_CMS:path.join(fixtureRoot,'synthetic.cms'),TEST_CONTEXT:JSON.stringify(cfg),TEST_ACKS:acks}}),
    upload:async req=>{calls.push(req.name);if(calls.length===1)return new Promise(()=>{});return{id:99};}}),/checkpoint_upload_failed/);
  assert.equal(calls.length,2);
  assert.deepEqual((await fs.readFile(acks,'utf8')).trim().split('\n').map(JSON.parse).map(a=>a.success),[false,true]);
});
test('unobserved child exit has a hard bound and never fabricates successful termination',async t=>{
  const cfg={...await context(t),ownerMilliseconds:10,cleanupMilliseconds:10};
  const logs=[], signals=[];
  const fake=new EventEmitter();fake.stdin=new PassThrough();fake.stdout=new PassThrough();fake.stderr=new PassThrough();
  fake.kill=signal=>{signals.push(signal);return false;};fake.unref=()=>{};
  const began=Date.now();
  await assert.rejects(p.supervise(cfg,{spawnOwner:()=>fake,log:x=>logs.push(x),killObservationMilliseconds:10}),/owner_timeout/);
  assert.deepEqual(signals,['SIGTERM','SIGKILL']);assert.ok(Date.now()-began<1000);
  const record=JSON.parse(logs.find(x=>x.startsWith('AQER_BRIDGE_OWNER_EXIT ')).split(' ').slice(1).join(' '));
  assert.equal(record.observed,false);assert.equal(record.code,null);assert.equal(record.signal,null);
});
