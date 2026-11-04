# Offline proposal: one-job owner JavaScript action

This is a locally tested supervisor and encrypted-checkpoint uploader component.
It has not run on GitHub or uploaded real account evidence. It is not an Android
acceptance result, a finished workflow, or proof that C1/C4/C2 passed.

## Why a JavaScript action

GitHub's artifact runtime token and result-service URLs are action runtime
credentials. This component runs as a Node 24 custom action rather than assuming
those credentials exist in a preceding shell step. The exact official
`actions/upload-artifact` revision
`ea165f8d65b6e75b540449e92b4886f43607fa02` declares `@actions/artifact` with
`^2.3.2`, and its lock resolves **2.3.2**. This action pins **2.3.2 exactly** and
derives its 152-package production dependency closure from that same official
lock, retaining resolved versions and integrity digests.

Official source references:

- https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/package-lock.json
- https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/src/shared/upload-artifact.ts
- https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/README.md#limitations

The pinned action documents 500 artifacts per job. This component does not test
the backend quota and does not infer it from newer toolkit versions.

The workflow must first run `npm ci --ignore-scripts --omit=dev` in this action
directory, outside the secret-bearing action step. Dependencies are not bundled.
The local validation performed a **dry-run offline lock resolution**, not a
network installation or real artifact-client upload. The workflow must also run
the independently reviewed source/APK guards and keep `permissions: contents:
read`; this component does not grant permissions or verify the git tree itself.

## Fixed context and child

The action requires Linux, the exact repository
`JJalal1/real-estate-uat-backend`, positive run/attempt identifiers,
`GITHUB_SHA`, and the reviewed manifest digest in
`AQER_BRIDGE_TOOLBUNDLE_SHA`. The latter must come from verified source, not a
received command. It launches only:

```
python3 -B <GITHUB_WORKSPACE>/scripts/run_phase1_native_bridge.py
  --run-root <RUNNER_TEMP>/aqer-phase1-bridge-<run_id>-<attempt>
```

The supervisor creates the fresh empty root with mode 0700. Python must accept
that existing empty private directory. Every `ACTIONS_*` variable is stripped
from Python's environment, including the artifact runtime token and both runtime
URLs. `GITHUB_TOKEN` is retained only for the owner's read-only command polling;
the existing UAT test-access variable is retained for normal account login.

The artifact upload runs in a short-lived Node worker. Only that worker inherits
the action runtime credentials; its copy omits the UAT access variable and
`GITHUB_TOKEN`. Its raw stdout/stderr is discarded, including library diagnostic
messages. IPC returns only validated actual artifact ID and optional digest.
An omitted digest stays null; no digest or ID is invented.

## Child NDJSON and ACK

Python stdout is a bounded control channel, not a logging channel. The only
accepted object has exactly these fields:

```json
{"event":"checkpoint_ready","seq":0,"checkpoint_dir":"checkpoints/000000"}
```

The path must be exactly derived from the allocated sequence. Normal sequences
start at zero, are contiguous, and are consumed before upload. A forward gap is
admitted only after the fully validated receipt proves it is a terminal
checkpoint. This covers early terminal sequence one and terminal evidence after
packaging allocated a checkpoint that failed before announcement. No fixture or
review checkpoint may use this exception; it cannot authorize a Root command or
any UI action. Zero is only a fixture
checkpoint; review and terminal checkpoints use positive sequences. A terminal
checkpoint must use a **fresh newly allocated** sequence and immutable path,
even if a preceding upload failed. Last command sequence is separate metadata
inside encrypted evidence. No Root command is expected for a terminal checkpoint.

After an upload attempt the supervisor writes one minimal ACK to Python stdin:

```json
{"event":"checkpoint_ack","seq":0,"success":true,"artifact_id":123,"digest":null}
```

On failure `success` is false and both metadata values are null. There is no
bridge-level retry of that checkpoint or artifact name. The official client can
have its own internal transport behavior; this component makes one client call.
ACK is sent only after the supervisor has cleared its in-flight upload state,
so a legitimate next announcement cannot race the ACK.

Raw Python stdout is never echoed; stderr is drained and discarded. Duplicate,
overlapping, oversized, malformed or path-substituted messages stop the owner.
After an upload failure, timeout or interruption, only one new terminal cleanup
checkpoint is admitted. The original action failure remains a failure even if
that terminal evidence uploads successfully.

## Checkpoint files

An announced directory contains exactly `checkpoint.cms` and
`PUBLIC_RECEIPT.json`. It and its parent directories must be private owned 0700
directories. Inputs must be regular owned 0600 single-link files; symlink,
hardlink, broad-mode, extra-file and escaping-path observations are refused.
Checks are repeated around an immutable staging copy and changes during reading
are refused. The producer is trusted reviewed code and must not mutate announced
checkpoints; this is not isolation from hostile code running as the same UID.

CMS is bounded to 256 MiB, checked for a complete DER EnvelopedData ContentInfo
(`1.2.840.113549.1.7.3`), and parsed by OpenSSL without output. This format check
does not decrypt or inspect its private evidence; the reviewed producer must
perform the actual encryption and privacy checks. The expected producer uses
OpenSSL AES-256-CBC CMS. No outer CMS AEAD claim is made.

The public receipt is flat strict JSON, at most 64 KiB. Duplicate decoded keys,
unknown fields, nested values, invalid types, wrong run/source identity and a
true acceptance flag are refused. Its exact fields are:

```
version repo run_id run_attempt source_sha toolbundle_sha seq kind phase cursor
checkpoint_challenge prev_result_sha cipher_sha cipher_bytes created_utc phase1_accepted
```

`cipher_sha` and `cipher_bytes` must match the actual staged CMS bytes. Only the
validated canonical public receipt and ciphertext enter the artifact. The
artifact name is unique: `aqer-bridge-<run_id>-<attempt>-<sequence:06d>`. It uses
three-day retention and compression level zero. Staging copies are removed after
each attempt. Root must separately download/decrypt and review actual frames.

## Deadlines and completion

The default owner lifetime is 6200 seconds; SIGTERM cleanup grace is at most
180 seconds. The workflow must reserve sufficient time around this action
(the planned owner has an earlier independent work/cleanup deadline). Unknown
message data and uploader failures never enter log messages.

Timeout, protocol failure or interruption requests SIGTERM on the known owner,
then SIGKILL after the bounded grace period. A further observation bound prevents
the supervisor from waiting indefinitely. An unobserved exit is recorded with
`observed:false` and null exit/signal values; it is not turned into exit zero.
Only a real close event supplies the observed exit code/signal. If observation
fails, local pipe handles are detached so the action can fail; GitHub's own
orphan cleanup is not claimed as an observed application or fixture cleanup.

Public supervisor logs contain fixed markers and one sanitized `owner_exit`
record only. Success requires a real owner exit zero, no prior failure, and a
successfully uploaded terminal checkpoint. That result establishes completion
of the owner process contract, not product acceptance or successful fixture
cleanup; Root must read the actual terminal evidence.

Python's signal handler must be idempotent during cleanup. A failed-upload ACK
and SIGTERM must not interrupt cleanup twice. Uncertain fixture operations must
never be replayed merely to obtain a clean exit. Abrupt runner loss and missing
terminal evidence remain unproven cleanup.

## Local verification

```
node --check index.js
node --test test_index.js
npm ci --dry-run --ignore-scripts --omit=dev --offline --no-audit --no-fund
```

Tests use generated short-lived test CMS keys and synthetic data in temporary
directories, fake owner subprocesses and fake upload functions. They make no
GitHub request, access no real task key or account, and run no emulator.
