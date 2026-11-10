'use strict';

// Offline proposal. No acceptance flags, auth snapshots or arbitrary upload paths.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawn, fork} = require('node:child_process');

const REPO = 'JJalal1/real-estate-uat-backend';
const OWNER_RELATIVE = 'scripts/run_phase1_native_bridge.py';
const CMS_LIMIT = 256 * 1024 * 1024;
const RECEIPT_LIMIT = 64 * 1024;
const LINE_LIMIT = 1024;
const RECEIPT_KEYS = ['version', 'repo', 'run_id', 'run_attempt', 'source_sha',
  'toolbundle_sha', 'seq', 'kind', 'phase', 'cursor', 'checkpoint_challenge',
  'prev_result_sha', 'cipher_sha', 'cipher_bytes', 'created_utc', 'phase1_accepted'];
const HEX64 = /^[0-9a-f]{64}$/;

class Refused extends Error {
  constructor(code) { super(code); this.code = code; }
}
function need(condition, code) { if (!condition) throw new Refused(code); }
function keysExactly(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));
}
function positive(value, max = Number.MAX_SAFE_INTEGER) {
  return Number.isSafeInteger(value) && value >= 1 && value <= max;
}
function canonical(value) {
  return JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(k => [k, value[k]])));
}

// Fixed messages and receipts are flat JSON. This scanner rejects duplicate
// decoded keys, nested content and trailing input before JSON.parse can hide it.
function parseFlatJSONUnsafe(raw, maximum) {
  need(Buffer.isBuffer(raw) && raw.length > 0 && raw.length <= maximum, 'json_bound');
  const text = new TextDecoder('utf-8', {fatal: true}).decode(raw);
  let i = 0;
  const ws = () => { while (i < text.length && /[\t\r\n ]/.test(text[i])) i++; };
  function string() {
    need(text[i] === '"', 'json_string');
    const begin = i++;
    let escaped = false;
    while (i < text.length) {
      const c = text[i++];
      if (escaped) { escaped = false; continue; }
      if (c === '\\') { escaped = true; continue; }
      if (c === '"') return JSON.parse(text.slice(begin, i));
    }
    throw new Refused('json_string');
  }
  ws(); need(text[i++] === '{', 'json_object'); ws();
  const result = Object.create(null);
  if (text[i] !== '}') {
    for (;;) {
      const name = string();
      need(!Object.hasOwn(result, name), 'json_duplicate_key');
      ws(); need(text[i++] === ':', 'json_colon'); ws();
      let value;
      if (text[i] === '"') value = string();
      else {
        const begin = i;
        while (i < text.length && !/[\t\r\n ,}]/.test(text[i])) i++;
        const token = text.slice(begin, i);
        need(/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$/.test(token), 'json_primitive');
        value = JSON.parse(token);
        need(typeof value !== 'number' || Number.isFinite(value), 'json_number');
      }
      result[name] = value; ws();
      if (text[i] === '}') break;
      need(text[i++] === ',', 'json_comma'); ws();
    }
  }
  need(text[i++] === '}', 'json_close'); ws();
  need(i === text.length, 'json_trailing');
  return result;
}
function parseFlatJSON(raw, maximum) {
  try{return parseFlatJSONUnsafe(raw,maximum);}
  catch(error){throw error instanceof Refused?error:new Refused('json_invalid');}
}

async function noSymlinkPath(filename) {
  need(path.isAbsolute(filename) && !filename.split(path.sep).includes('..'), 'absolute_path_required');
  let current = path.parse(filename).root;
  for (const piece of filename.slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, piece);
    const stat = await fsp.lstat(current);
    need(!stat.isSymbolicLink(), 'symlink_refused');
  }
}
async function privateDirectory(directory) {
  await noSymlinkPath(directory);
  const stat = await fsp.lstat(directory);
  need(stat.isDirectory() && stat.uid === process.geteuid() && (stat.mode & 0o777) === 0o700,
    'private_directory_required');
}
async function openPrivateFile(filename, maximum) {
  await noSymlinkPath(filename);
  const preliminary=await fsp.lstat(filename);
  need(preliminary.isFile(),'private_regular_file_required');
  let handle;
  try{handle=await fsp.open(filename, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);}
  catch(_){throw new Refused('private_file_unobserved');}
  try {
    const stat = await handle.stat();
    need(stat.isFile() && stat.nlink === 1 && stat.uid === process.geteuid() &&
      (stat.mode & 0o777) === 0o600 && stat.size > 0 && stat.size <= maximum,
    'private_regular_file_required');
    return {handle, stat};
  } catch (_) { await handle.close(); throw new Refused('private_regular_file_required'); }
}
function unchanged(before, after) {
  return before.dev === after.dev && before.ino === after.ino && before.size === after.size &&
    before.mtimeMs === after.mtimeMs && before.ctimeMs === after.ctimeMs;
}
function validateReceipt(value, cfg, seq, cipherSize, cipherHash) {
  need(keysExactly(value, RECEIPT_KEYS), 'receipt_schema');
  need(value.version === 1 && value.repo === REPO && value.run_id === cfg.runId &&
    value.run_attempt === cfg.attempt && value.source_sha === cfg.source &&
    value.toolbundle_sha === cfg.bundle && value.seq === seq && value.phase1_accepted === false,
  'receipt_identity');
  const phases = cfg.phase23 ? ['R0','R1','R2','R3','R4','R5','R6'] : ['C1','C4','C2','C5'];
  need(phases.includes(value.phase) && typeof value.cursor === 'string' &&
    /^[A-Z][A-Z0-9_]{0,63}$/.test(value.cursor), 'receipt_phase');
  need(['fixture_checkpoint','review_checkpoint','terminal_checkpoint'].includes(value.kind) &&
    ((seq === 0 && value.kind === 'fixture_checkpoint') ||
     (positive(seq, 10000) && value.kind !== 'fixture_checkpoint')), 'receipt_kind');
  need(['checkpoint_challenge','prev_result_sha','cipher_sha'].every(k =>
    typeof value[k] === 'string' && HEX64.test(value[k])), 'receipt_digest');
  need(Number.isSafeInteger(value.cipher_bytes) && value.cipher_bytes === cipherSize &&
    value.cipher_sha === cipherHash, 'receipt_cipher_binding');
  need(typeof value.created_utc === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(value.created_utc) &&
    new Date(value.created_utc).toISOString() === value.created_utc.replace('Z', '.000Z'), 'receipt_utc');
  return value;
}

function cmsEnvelopeHeader(prefix, total) {
  let at = 0;
  need(prefix[at++] === 0x30, 'cms_content_info');
  let length = prefix[at++];
  if (length & 0x80) {
    const count = length & 0x7f;
    need(count >= 1 && count <= 4 && prefix[at] !== 0, 'cms_der_length');
    length = 0;
    for (let n = 0; n < count; n++) length = length * 256 + prefix[at++];
    need(length >= 128, 'cms_der_length');
  }
  need(at + length === total && prefix[at++] === 0x06 && prefix[at++] === 9, 'cms_der_bound');
  const enveloped = Buffer.from('2a864886f70d010703', 'hex');
  need(prefix.subarray(at, at + 9).equals(enveloped) && prefix[at + 9] === 0xa0,
    'cms_enveloped_data_required');
}
function verifyCms(filename, spawnProcess = spawn) {
  return new Promise((resolve, reject) => {
    const child = spawnProcess('openssl', ['cms','-cmsout','-inform','DER','-noout','-in',filename],
      {stdio: ['ignore','ignore','ignore']});
    let settled = false;
    const done = ok => { if (!settled) { settled = true; clearTimeout(timer); ok ? resolve() : reject(new Refused('cms_parse_failed')); } };
    const timer = setTimeout(() => { child.kill('SIGKILL'); done(false); }, 10000);
    child.once('error', () => done(false)); child.once('close', code => done(code === 0));
  });
}

async function prepareCheckpoint(cfg, seq, options = {}) {
  need(Number.isSafeInteger(seq) && seq >= 0 && seq <= 10000, 'checkpoint_sequence');
  const relative = `checkpoints/${String(seq).padStart(6,'0')}`;
  const directory = path.join(cfg.root, relative);
  await privateDirectory(cfg.root);
  await privateDirectory(path.join(cfg.root, 'checkpoints'));
  await privateDirectory(directory);
  const names = (await fsp.readdir(directory)).sort();
  need(names.length === 2 && names[0] === 'PUBLIC_RECEIPT.json' && names[1] === 'checkpoint.cms',
    'checkpoint_file_allowlist');
  const cms = await openPrivateFile(path.join(directory, 'checkpoint.cms'), CMS_LIMIT);
  let receipt;
  let staging;
  try {
    const receiptFile = await openPrivateFile(path.join(directory, 'PUBLIC_RECEIPT.json'), RECEIPT_LIMIT);
    try {
      const data = await receiptFile.handle.readFile();
      need(unchanged(receiptFile.stat, await receiptFile.handle.stat()), 'receipt_changed');
      receipt = parseFlatJSON(data, RECEIPT_LIMIT);
    } finally { await receiptFile.handle.close(); }
    const parent = path.join(cfg.root, 'uploads');
    try { await fsp.mkdir(parent, {mode:0o700}); } catch (e) { need(e.code === 'EEXIST', 'upload_directory'); }
    await privateDirectory(parent);
    staging = await fsp.mkdtemp(path.join(parent, `checkpoint-${String(seq).padStart(6,'0')}-`));
    await fsp.chmod(staging,0o700);
    const target = path.join(staging,'checkpoint.cms');
    const dest = await fsp.open(target, fs.constants.O_WRONLY | fs.constants.O_CREAT |
      fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    const hash = crypto.createHash('sha256');
    let bytes = 0;
    const buffer = Buffer.alloc(128 * 1024);
    let prefix;
    try {
      for (;;) {
        const {bytesRead} = await cms.handle.read(buffer,0,buffer.length,null);
        if (!bytesRead) break;
        if (!prefix) prefix = Buffer.from(buffer.subarray(0,Math.min(bytesRead,64)));
        bytes += bytesRead; need(bytes <= CMS_LIMIT && bytes <= cms.stat.size, 'cipher_size_changed');
        hash.update(buffer.subarray(0,bytesRead));
        let offset = 0;
        while (offset < bytesRead) {
          const written = await dest.write(buffer,offset,bytesRead-offset,null);
          need(written.bytesWritten > 0,'cipher_copy_failed'); offset += written.bytesWritten;
        }
      }
      need(bytes === cms.stat.size && unchanged(cms.stat,await cms.handle.stat()), 'cipher_changed');
      await dest.sync();
    } finally { await dest.close(); }
    cmsEnvelopeHeader(prefix || Buffer.alloc(0),bytes);
    validateReceipt(receipt,cfg,seq,bytes,hash.digest('hex'));
    await (options.verifyCms || verifyCms)(target);
    const receiptTarget = path.join(staging,'PUBLIC_RECEIPT.json');
    await fsp.writeFile(receiptTarget,canonical(receipt)+'\n',{mode:0o600,flag:'wx'});
    return {directory:staging,files:[target,receiptTarget],receipt};
  } catch (e) {
    if (staging) await fsp.rm(staging,{recursive:true,force:true});
    throw e instanceof Refused ? e : new Refused('checkpoint_unobserved');
  } finally { await cms.handle.close(); }
}

function childEnvironment(env) {
  const result = {...env};
  for (const name of Object.keys(result)) if (name.startsWith('ACTIONS_')) delete result[name];
  return result;
}
function configFromEnvironment(env) {
  need(process.platform === 'linux' && env.GITHUB_ACTIONS === 'true' &&
    env.GITHUB_REPOSITORY === REPO, 'reviewed_ci_context_required');
  need(/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID || '') &&
    /^[1-9][0-9]{0,3}$/.test(env.GITHUB_RUN_ATTEMPT || ''), 'run_identity');
  need(/^[0-9a-f]{40}$/.test(env.GITHUB_SHA || '') &&
    HEX64.test(env.AQER_BRIDGE_TOOLBUNDLE_SHA || ''), 'source_identity');
  need(path.isAbsolute(env.RUNNER_TEMP || '') && path.isAbsolute(env.GITHUB_WORKSPACE || ''), 'runner_paths');
  const number = (name,fallback,min,max) => {
    const raw = env[name] || String(fallback);
    need(/^[1-9][0-9]*$/.test(raw),'bounded_timeout');
    const n=Number(raw); need(Number.isSafeInteger(n) && n>=min && n<=max,'bounded_timeout');return n;
  };
  const phase23 = env.GITHUB_REF === 'refs/heads/work/phase23-acceptance-20261111';
  return {root:path.join(env.RUNNER_TEMP,`${phase23 ? 'aqer-phase23' : 'aqer-phase1'}-bridge-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`),
    script:path.join(env.GITHUB_WORKSPACE,phase23 ? 'scripts/run_phase23_native.py' : OWNER_RELATIVE),runId:env.GITHUB_RUN_ID,phase23,
    attempt:Number(env.GITHUB_RUN_ATTEMPT),source:env.GITHUB_SHA,bundle:env.AQER_BRIDGE_TOOLBUNDLE_SHA,
    ownerMilliseconds:number('INPUT_OWNER-TIMEOUT-SECONDS',6200,60,7200)*1000,
    cleanupMilliseconds:number('INPUT_CLEANUP-GRACE-SECONDS',180,5,180)*1000};
}

async function supervise(cfg, options={}) {
  await noSymlinkPath(cfg.script);
  const source=await fsp.lstat(cfg.script);
  need(source.isFile() && source.nlink===1,'fixed_owner_script_required');
  await noSymlinkPath(path.dirname(cfg.root));
  await fsp.mkdir(cfg.root,{mode:0o700});
  await privateDirectory(cfg.root);
  const launch=options.spawnOwner || spawn;
  const upload=options.upload || uploadThroughWorker;
  const log=options.log || (code=>process.stdout.write(code+'\n'));
  const child=launch('python3',['-B',cfg.script,'--run-root',cfg.root],{
    env:childEnvironment(options.env || process.env),stdio:['pipe','pipe','pipe']});
  let failure=null, expected=0, allocations=0, active=false, buffer=Buffer.alloc(0), closed=false;
  let lastKind=null, hardKill=null, observeKill=null, terminalAttempted=false;
  let uploadOperation=Promise.resolve(), resolveExit;
  const exit=new Promise(resolve=>{resolveExit=resolve;});
  const stop=code=>{
    failure=failure || code;
    if (!closed && !hardKill) {
      child.kill('SIGTERM');
      hardKill=setTimeout(()=>{
        if(!closed){
          child.kill('SIGKILL');
          observeKill=setTimeout(()=>resolveExit({code:null,signal:null,observed:false}),
            options.killObservationMilliseconds || 10000);
        }
      },cfg.cleanupMilliseconds);
    }
  };
  const ack=record=>{
    if (!closed && child.stdin.writable) child.stdin.write(canonical(record)+'\n',()=>{});
  };
  child.once('close',(code,signal)=>{closed=true;resolveExit({code,signal,observed:true});});
  child.once('error',()=>stop('owner_spawn_failed'));
  child.stdin.on('error',()=>stop('owner_stdin_failed'));
  child.stdout.on('error',()=>stop('owner_stdout_failed'));
  child.stderr.on('error',()=>stop('owner_stderr_failed'));
  const onSignal=()=>stop('owner_interrupted');
  process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
  const deadline=setTimeout(()=>stop('owner_timeout'),cfg.ownerMilliseconds);
  child.stderr.resume();
  child.stdout.on('data',chunk=>{
    if(terminalAttempted){stop('checkpoint_after_terminal');return;}
    const terminalOnly=Boolean(failure);
    if(terminalOnly && (!['checkpoint_upload_failed','owner_timeout','owner_interrupted'].includes(failure) || terminalAttempted))return;
    buffer=Buffer.concat([buffer,chunk]);
    if(buffer.length>LINE_LIMIT){stop('owner_message_bound');return;}
    for(;;){
      const cut=buffer.indexOf(10);if(cut<0)break;
      const line=buffer.subarray(0,cut);buffer=buffer.subarray(cut+1);
      if(active){stop('overlapping_checkpoint');return;}
      let message;
      try{
        message=parseFlatJSON(line,LINE_LIMIT);
        need(keysExactly(message,['event','seq','checkpoint_dir']) && message.event==='checkpoint_ready' &&
          Number.isSafeInteger(message.seq) && message.seq>=expected && message.seq<=10000 &&
          message.checkpoint_dir===`checkpoints/${String(message.seq).padStart(6,'0')}`,'owner_message_schema');
      }catch(_){stop('owner_message_invalid');return;}
      const terminalGap=message.seq!==expected;
      expected=message.seq+1;allocations++;
      active=true;
      uploadOperation=(async()=>{
        let checkpoint, acknowledgement;
        try{
          checkpoint=await prepareCheckpoint(cfg,message.seq,options);
          need(!terminalGap || checkpoint.receipt.kind==='terminal_checkpoint','gapped_terminal_checkpoint_required');
          need(!terminalOnly || checkpoint.receipt.kind==='terminal_checkpoint','terminal_checkpoint_required');
          if(checkpoint.receipt.kind==='terminal_checkpoint')terminalAttempted=true;
          let uploadTimer;
          const result=await Promise.race([
            upload({name:`aqer-bridge-${cfg.runId}-${cfg.attempt}-${String(message.seq).padStart(6,'0')}`,
              files:checkpoint.files,rootDirectory:checkpoint.directory}),
            new Promise((_,reject)=>{uploadTimer=setTimeout(()=>reject(new Refused('upload_timeout')),
              options.uploadMilliseconds || 240000);})
          ]).finally(()=>clearTimeout(uploadTimer));
          need(result && positive(result.id) && (result.digest===undefined || result.digest===null ||
            (typeof result.digest==='string' && HEX64.test(result.digest))),'artifact_receipt_invalid');
          need(!failure || (terminalOnly && checkpoint.receipt.kind==='terminal_checkpoint'),'owner_stopping');
          acknowledgement={event:'checkpoint_ack',seq:message.seq,success:true,artifact_id:result.id,digest:result.digest || null};
          lastKind=checkpoint.receipt.kind;log('AQER_BRIDGE_CHECKPOINT_UPLOADED');
        }catch(_){
          acknowledgement={event:'checkpoint_ack',seq:message.seq,success:false,artifact_id:null,digest:null};
          stop('checkpoint_upload_failed');
        }finally{
          if(checkpoint){
            try{await fsp.rm(checkpoint.directory,{recursive:true,force:true});}
            catch(_){acknowledgement={event:'checkpoint_ack',seq:message.seq,success:false,artifact_id:null,digest:null};stop('checkpoint_upload_failed');}
          }
          active=false;
        }
        ack(acknowledgement);
      })();
    }
  });
  log('AQER_BRIDGE_OWNER_STARTED');
  let ended;
  try{
    ended=await exit;
    if(!ended.observed){
      child.stdin.destroy();child.stdout.destroy();child.stderr.destroy();
      if(typeof child.unref==='function')child.unref();
    }
    await uploadOperation;
  }
  finally{
    clearTimeout(deadline);if(hardKill)clearTimeout(hardKill);if(observeKill)clearTimeout(observeKill);
    process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);
  }
  log('AQER_BRIDGE_OWNER_EXIT '+canonical({event:'owner_exit',observed:ended.observed===true,
    code:Number.isInteger(ended.code)?ended.code:null,
    signal:typeof ended.signal==='string' && /^SIG[A-Z0-9]+$/.test(ended.signal)?ended.signal:null,
    checkpoints:allocations}));
  need(!failure, failure || 'owner_failed');
  need(buffer.length===0 && ended.observed===true && ended.code===0 && ended.signal===null,'owner_exit_unconfirmed');
  need(lastKind==='terminal_checkpoint','owner_terminal_checkpoint_missing');
  log('AQER_BRIDGE_OWNER_COMPLETED');
  return {status:'owner_completed',checkpoints:allocations,code:ended.code};
}

function uploadThroughWorker(request) {
  return new Promise((resolve,reject)=>{
    const env={...process.env};delete env.AQER_PHASE1_TEST_ACCESS_JSON;delete env.GITHUB_TOKEN;
    const child=fork(__filename,['--artifact-worker'],{env,stdio:['ignore','pipe','pipe','ipc']});
    child.stdout.resume();child.stderr.resume();
    let settled=false;
    const finish=(error,value)=>{if(!settled){settled=true;clearTimeout(timer);child.kill('SIGTERM');error?reject(new Refused('artifact_upload_failed')):resolve(value);}};
    const timer=setTimeout(()=>{child.kill('SIGKILL');finish(true);},240000);
    child.once('error',()=>finish(true));
    child.once('exit',()=>{if(!settled)finish(true);});
    child.once('message',message=>{
      if(keysExactly(message,['event','id','digest']) && message.event==='uploaded' && positive(message.id) &&
        (message.digest===null || (typeof message.digest==='string' && HEX64.test(message.digest))))
        finish(false,{id:message.id,digest:message.digest});
      else finish(true);
    });
    child.send(request,error=>{if(error)finish(true);});
  });
}

async function artifactWorker() {
  process.once('message',async request=>{
    try{
      need(keysExactly(request,['name','files','rootDirectory']) &&
        /^aqer-bridge-[1-9][0-9]{0,19}-[1-9][0-9]{0,3}-[0-9]{6}$/.test(request.name) &&
        Array.isArray(request.files) && request.files.length===2 &&
        path.isAbsolute(request.rootDirectory),'worker_request');
      const expected=['checkpoint.cms','PUBLIC_RECEIPT.json'];
      need(request.files.every((f,i)=>f===path.join(request.rootDirectory,expected[i])),'worker_files');
      await privateDirectory(request.rootDirectory);
      for(const file of request.files){const h=await openPrivateFile(file,file.endsWith('.cms')?CMS_LIMIT:RECEIPT_LIMIT);await h.handle.close();}
      const artifact=require('@actions/artifact').default;
      need(artifact && typeof artifact.uploadArtifact==='function','official_artifact_client_missing');
      const result=await artifact.uploadArtifact(request.name,request.files,request.rootDirectory,
        {compressionLevel:0,retentionDays:3});
      need(result && positive(result.id),'artifact_identity_missing');
      const digest=result.digest===undefined?null:result.digest;
      need(digest===null || (typeof digest==='string' && HEX64.test(digest)),'artifact_digest_invalid');
      process.send({event:'uploaded',id:result.id,digest},()=>process.exit(0));
    }catch(_){process.exit(1);}
  });
}

if(require.main===module){
  if(process.argv[2]==='--artifact-worker') artifactWorker();
  else Promise.resolve().then(()=>supervise(configFromEnvironment(process.env))).catch(error=>{
    const code=error instanceof Refused && /^[a-z_]+$/.test(error.code)?error.code:'action_failed';
    process.stdout.write(`::error::AQER_BRIDGE_${code.toUpperCase()}\n`);process.exitCode=1;
  });
}
module.exports={Refused,parseFlatJSON,configFromEnvironment,childEnvironment,validateReceipt,
  cmsEnvelopeHeader,verifyCms,prepareCheckpoint,supervise,uploadThroughWorker,REPO,OWNER_RELATIVE,CMS_LIMIT};
