# Same-job owner components: offline handoff

These are tested components for the reviewed GitHub entry. They do not start an
emulator, discover credentials, make account calls, upload real evidence, or
establish Phase 1 acceptance. The production entry and workflow must compose
the separately reviewed VM lifecycle, controller, adapter and one-shot driver.
The kernel's direct CLI deliberately exits `AQER_OWNER_ENTRY_NOT_WIRED`.

## Deployment and dependencies

Copy these Python modules to `scripts/phase1_bridge/owner/`, the frozen protocol
to sibling `protocol/`, and the action to `.github/actions/phase1-review/`.
The action launches only `scripts/run_phase1_native_bridge.py --run-root
<fixed-private-root>`. The entry is supplied separately by Root. Imports retain
the sibling owner/protocol layout. Use Python 3.12, `cryptography==50.0.2`,
`Pillow==12.3.0`, OpenSSL and `ffprobe`; this work adds no product dependency.
The Node 24 action pins `@actions/artifact==2.3.2` and its official lock closure.
Install/check all dependencies before the secret-bearing action step.

The action precreates an empty, private, owned 0700 run root. The packager creates
its own `checkpoints/` and `.checkpoint-staging/` children. Evidence must use a
separate private owned directory. All files admitted for packaging are regular
owned 0600 single-link files. Same-UID source is trusted and reviewed; directory
checks are not OS isolation from malicious code executing as the same owner.

## Kernel and controller composition

```python
session = OwnerSession(
    root=run_root, controller=controller, channel=channel, packager=packager,
    job_key=job_key, root_public=pinned_root_public,
    checkpoint_io=StdIOBridge(root=run_root), budget=Budget())
```

The adapter receives `lambda: session.active_authority` and the independent
`lambda: session.current_context`. The latter returns the owner's admitted input
context during a segment, including cleanup C5, and its held context otherwise.
`current_input_context` is available when an active admission alone is desired.
Never derive the independent getter from `active_authority.context` itself.

Required controller methods are:

| Method | Required meaning |
| --- | --- |
| `prepare_runtime()` | Boot the single owned VM only. No input/auth/API seed. |
| `prepare_initial_native()` | Under initial lease: install, configure, verify capability/clock and actual native public feed; literal `True` after proof. |
| `bootstrap_fixture()` | Normal API title-only seed after the public-feed proof. Retain exact known fixture/baseline in RAM. |
| `fixture_summary()` | Exact minimized `{fixture, baseline}` described below. |
| `quiesce_for_checkpoint()` | Stop evidence writers using appropriate authority; no unreviewed phase extension. |
| `initial_c1()` | Same initial lease: actual normal native login/create/photo/save/restore; literal `True` after observations. |
| `snapshot()` | Exact `{phase, cursor, stage, evidence}` for current held stage. |
| `fresh_scene_matches(review, snapshot)` | Read-only actual scene/binding validation; literal `True` only after exact match. |
| `advance(review)` | Phase-specific signed Root record validation and one actual bounded segment; literal `True` only after actual postcondition. |
| `finished()` | Actual collection finished, separate from Root acceptance. |
| `private_aliases()` | Currently known private values as a RAM-only tuple, never printed or serialized. |
| `uncertain()` | Actual permanent one-shot admission uncertainty. Cleanup cannot clear it. |
| `validate_promoted_identity(id)` | Fresh exact known fixture/property/actor pin; literal `True` only after proof. |
| `fixture_removed_confirmed()` | Actual exact deletion postconditions, when a previously known link disappears. |
| `stop_writers(deadline=...)` | Bounded owned recorder/writer shutdown. |
| `cleanup_once(deadline=...)` | One strict selected C5 cleanup attempt; literal `True` requires actual identity/media/baseline/HTTP postconditions. Never retry an uncertain delete. |
| `close_runtime(deadline=...)` | Actual created/exit/group observations specified below. |
| `clear_private_state()` | Drop in-memory private references after terminal packaging; no memory-erasure claim. |

`fixture` has exactly `draft_uuid`, `tag`, `actor_id` (28), `property_id` (null or
positive integer). `baseline` has exactly `properties` and `drafts`, each exactly
`{count, sha256}`. No original rows, full API state, credentials, private aliases,
tokens, app data or AVD enters a checkpoint. The owner pins UUID/tag/actor and
baseline, verifies a newly promoted Property, and refuses identity replacement.

The runtime receipt contains explicit `vm_created` and `relay_created` booleans;
`vm_exit_code` and `relay_exit_code` are actual integer poll results for each
created process and null only for a process never created. A created VM also
requires `owned_process_group_absence_observed: true`. The controller may set
`all_created_processes_observed_ended: true` only after those observations. Missing
codes or unknown creation flags cannot become a successful runtime receipt.

## Authority and order

After VM boot, the owner issues **one** source-plan lease capped at 600 seconds.
Its distinct C1/`INITIAL_C1` context has a random source-plan challenge and an
explicit zero planned cipher hash; it is not a Root-reviewed checkpoint. That
same lease covers native preparation/public feed, API title bootstrap, immutable
checkpoint zero ACK, and initial C1. It is never split, renewed or extended.

Checkpoint zero's cursor is `PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP`: the API
title-only PUT already happened. An abrupt runner loss before upload zero is
not recoverable from an artifact created by this component. It must never be
described as a checkpoint preceding all business mutations.

Each later held stage is quiesced, sealed, uploaded and acknowledged before its
command poll. Root checks the actual artifact and signs the exact run/attempt/
source/tool/sequence/phase/cursor/challenge/cipher/previous-result context.
Invalid or expired unconsumed envelopes cause no input and can be replaced at
the same fixed path while the bounded wait remains. The durable protocol ledger
reserves a verified command before scene matching and dispatch. An uncertain
segment stays consumed and ends this owner; it is never rerun for a cleaner
receipt. Nonvisual stages still require a fresh signed advance, but must never
invent positive visual review flags.

`VerifiedGrant`, `SourcePlanLease` and `CleanupLease` are distinct exact trusted
classes with readonly `authority_kind`, `context` and `monotonic_deadline`.
Root grants expose the actual signed `expires_utc` and actual
`review_completed_utc`; they validate exact Context and signed freshness before
each mutation. Review UTC uses whole seconds, age <=120 seconds, future skew
<=5 seconds and no later than issued UTC +5 seconds. No monotonic Root review
time is synthesized. The per-input minimum budget must fit both the original
monotonic deadline and actual UTC expiry.

The reviewed adapter and guest receiver must enforce the exact signed deadline
before **every** actual mutation, including nested account tap/set/scroll,
native authentication, raw back/app start/stop, OS picker and recorder paths.
Root guest deadlines use integer epoch milliseconds converted from the exact
signed UTC, with no refresh or rounding. A host check by itself cannot prove a
future guest input occurred before expiry if instrumentation startup stalled.
The distinct initial source lease is the agreed initial-only exception.

Default work budget is 5400 seconds; cleanup reserve is 600 seconds; each Root
hold is 300 seconds. Poll/network/upload/controller calls must be bounded.
Every controller operation must cap its own HTTP/subprocess/native work using
the active authority's original deadline or the passed cleanup deadline; the
kernel cannot preempt an arbitrary blocking Python callback. Cleanup on early
failure is bounded from that failure time, not allowed to run until the end of
the full 90-minute work budget. Repeated SIGTERM is idempotent and cannot revoke
the cleanup authority a second time.

CleanupLease is only for the fixed owner cleaner, never a phase executor. It
cannot clear one-shot uncertainty. With uncertain guest admission only host
app-stop/recorder-stop categories remain; no more taps, authentication or
snapshots may be admitted through the helper. Native cleanup, when provable,
has a conservative whole-second UI expiry capped at 120 seconds, while fixed
API/VM teardown remains bounded by the cleanup reserve. The strict cleaner must
stop native writers and delete the known promoted Property before its known
Draft, with exact known identity and original baseline protection.

## Transport and encryption contracts

`CommandChannel(run_id, run_attempt, read_only_token)` only GETs:

```
https://api.github.com/repos/JJalal1/real-estate-uat-backend/contents/
phase1-commands/<run_id>/<run_attempt>/<seq6>.json
?ref=work%2Fphase1-root-review-20261104
```

That branch and path are constants. No command checkout/exec, redirect,
`download_url`, remote script or custom host is followed. Inline base64 and
actual Git blob SHA are verified after exact GitHub Contents schema/size checks.
HTTP has a 20-second transport timeout; the owner rechecks hold/work time after
poll and before dispatch. An unavailable token is a fixed refusal, never a
reason to fall back to broader credentials or write permissions.

`CheckpointPackager(...)` receives trusted five-field identity, pinned **public**
recipient certificate and digest, job X25519 public bytes and pinned Root key ID.
`seal(...)` returns `SealedCheckpoint(public_receipt, held_context, directory)`.
The `identity` getter returns a fresh copy. `held_context` is an exact protocol
Context dictionary only for review checkpoints. The private X25519 key and
credentials stay in RAM; this component never serializes or reads a private
signing/decryption task key.

Only `checkpoint.cms` and `PUBLIC_RECEIPT.json` leave the packager. Inner
`CHECKPOINT.json.checkpoint` exactly equals PUBLIC metadata **minus**
`cipher_sha` and `cipher_bytes`; `context_without_cipher` omits only `cipher_sha`
for review checkpoints and is null for fixture/terminal checkpoints. The actual
outer CMS hash cannot be encrypted inside its own plaintext. Root must compare
inner/public metadata and reconstruct the full context using the verified
actual ciphertext digest. Actual media metadata/hash/dimensions/provenance is
preserved; `official_emulator_console_host_png` is admitted as the actual host
console marker without relabeling. Duration is exact decimal text, not rounded.
Producer privacy guards remain mandatory before exporting media; the packager
does not visually recognize credential pixels.

Every allocation consumes a fresh sequence even if packaging or upload fails.
The final cleanup checkpoint uses a new sequence; an early terminal is sequence
one when no zero was allocated. Never overwrite/reupload an ambiguous artifact.
The JS action allows only validated terminal forward gaps for unannounced failed
allocations. `StdIOBridge` emits the fixed checkpoint-ready line and accepts only
the exact bounded ACK; `last_ack` contains observed artifact ID and optional
artifact digest. Those are transport metadata, separate from checkpoint
ciphertext hash, Root review and product acceptance.

`OwnerResult` and every public receipt always report `phase1_accepted=false`.
Collection, cleanup, VM termination, successful upload and Root acceptance are
separate observations. Real GitHub/native evidence and Root review are required
to close the actual phase.

## Local verification

```
python3 -B -m unittest -q test_checkpoint_io.py test_owner_components.py test_checkpoint_packager.py
```

Tests use synthetic test keys, certificates, media and fake controller/device
callbacks in temporary directories. They include actual CMS encrypt/decrypt,
exact fractional video metadata, actual OS-pipe ACKs and real protocol/packager
composition. The separately frozen protocol has 39 tests and the action 25.
See `OFFLINE_OWNER_RECEIPT.json` and `action/OFFLINE_ACTION_RECEIPT.json` for
actual run receipts. These tests do not prove the real controller/native flow.
