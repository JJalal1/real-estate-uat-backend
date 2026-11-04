# Fix6 same-job entry proposal (entry-fix5 source directory)

Deploy `run_phase1_native_bridge.py` as `scripts/run_phase1_native_bridge.py` and
this README/test as `scripts/phase1_bridge/entry/{README.md,test_entry.py}`. Import
is inert. The entry does no work until one explicit CLI mode is selected:

```
python3 -B scripts/run_phase1_native_bridge.py --source-only [--github-env]
python3 -B scripts/run_phase1_native_bridge.py --offline-tests
python3 -B scripts/run_phase1_native_bridge.py --run-root <fixed-private-root>
```

The action supplies the last command with the exact fresh empty 0700 directory
`RUNNER_TEMP/aqer-phase1-bridge-<run_id>-<run_attempt>`. There is no generic module,
command URL, authentication-file, private-key or VM-address option.

`EXPECTED_FILES` is the exact 66-file deployment allowlist. Root vendors these
files, expands the existing prepare guard's ALLOWED set to exactly those paths
plus the manifest, then writes `scripts/phase1_bridge/tool_manifest.json` with
exact schema `{version:1,files:{repoRelativePath:lowercaseSHA256}}`. The manifest
does not hash itself. Tool bundle SHA is SHA256 of the actual manifest bytes,
including their chosen newline/format; no second normalized digest is used.
Every listed file is checked against its actual bytes with no symlink path
components, hardlinks, nonregular files or oversized input. Unknown/missing
paths, duplicate JSON keys and incorrect types fail closed.

Source-only verification checks the fixed Actions repository/ref/push/source/
run/attempt/default UAT origin, actual workspace, exact manifest and reviewed
Root public key. It requires the final paired probe SHA
`6077fd1d16fe02764c3fcccb7c69c1839660fd0d4283c1a27b7a5436a52f0ced`
and Java SHA
`56b9199ea3312f55746ea12176367c26b8ccabeb13981a93f2fd7a0bde2b2a5f`.
The actual existing `prepare.guard(env)` then checks git HEAD against the Actions
source, the exact baseline diff allowlist, original unchanged mobile/backend
trees, clean tracked paths and pinned public recipient certificate/expiry. No
fixture, native action or source receipt is synthesized. `--github-env` appends
only the verified public bundle SHA after all checks, through an owned bounded
file below RUNNER_TEMP with no symlink components.

Before any git/SDK subprocess, the two authorized runtime channels are popped
from actual `os.environ`: the read-only GitHub token and test-access JSON. Only
OS/SDK/CA/proxy allowlist values remain in the process environment. Public CI
identity is retained separately. The probe receives only that approved mapping
and a temporary test-access field for the reviewed validator. All three known
roles remain in the original RAM pool; raw JSON is dropped after construction.
The GitHub token is kept only in RAM for the fixed read-only channel and private
redaction set. It never enters probe/VM/subprocess environments. No Root signing
private key is loaded or sent to CI.

The entry imports the real frozen runtime modules and the final paired base.
One C2 module instance supplies its role installer, Controller and dispatcher,
preserving exact KnownRoleMemory class identity. The owner getters resolve late
to actual `active_authority` and independent `current_context`. Source-plan and
Root command order remains the frozen OwnerSession/Controller order; the entry
does not supply success stubs or affirmative review flags.

Initial C1 retains all current Home readiness, stable Add target, exact owned
title and bounded title-settling checks before any facts. It does not collect
the additional pre-input Home/basics/title diagnostic PNGs. Those diagnostic
methods retain their strict capture guards for explicit diagnostic use. C1
acceptance still requires the actual photo/restoration PNGs and both original
host clips, with the unchanged full privacy, identity and media validators.

The owned VM callback computes a bounded boot duration from the owner's work
deadline and requires actual API36/KVM boot/CE readiness plus a live owned
process. Before any application install or account action, it makes one bounded
clock preparation on this disposable userdebug emulator: root adbd, verify UID0,
set Toybox date from the actual host UTC with its fractional seconds, unroot and
verify the original shell UID2000. Raw epoch values and command output are never
retained. The original later conservative guest/host interval must still fall
within +/-250ms; preparation alone creates no clock acceptance and cannot be
replayed. It translates or extends no signed expiry. The authoritative commands
are documented in the AOSP adb man page and Toybox date.c sources.
Close maps the actual VM parent exit/group observations into the exact
six-field controller receipt. No relay is created by this entry, so relay fields
honestly say false/null. Missing poll results cannot become zero or confirmed
termination. Actual role/API/session/fixture cleanup remains the strict original
controller cleaner. A cleanup subprocess uses the original CleanupLease reserve
after the work deadline; Root/source leases already include the work cap.

The helper identity callback only runs fixed read-only SDK adb observations on
the owned `emulator-5554`: `pm path com.aqer.phase1.input`, then `sha256sum` of the
single strictly validated `/data/app/.../base.apk`. The actual installed hash
must equal the prepared `input.apk` hash and source-bound APK verification
receipt. It does not read app storage, pull an APK, inspect credentials or widen
the adapter's transport allowlist. Capability is checked separately by the real
adapter. Native probe commands retain the original checked delivery behavior
and cap subprocess timeout by the active authority's original deadline.

Guest UTC is observed with `date -u +%s%3N`, bracketed by host UTC and monotonic
time. It must produce exact13-digit milliseconds, a <=2s observation, consistent
host elapsed clocks, and a conservative full offset interval within ±250ms.
Unsupported formatting, lag, clock jump or a wide interval refuses. This is a
bounded synchronization observation, not zero clock skew. The guest receives
the original signed expiry unchanged; there is no clamp, renewal or invented
review time. The AOSP Toybox date source implements one-digit precision before
`N`; the actual runtime parser still fails closed if this image differs:
https://android.googlesource.com/platform/external/toybox/+/master/toys/posix/date.c
(Reviewed file blob: `81e6b7e39645876be7e92196c7a59465572a53ea`.)

Current RAM aliases include both the probe's roles/tokens and FixtureApi's
private-value set. The entry's Controller subclass exposes their fresh union to
protocol checks. A wrapper scans that fresh union before every packager seal,
then delegates to the frozen minimizer/encryptor. Later API bearer values are
therefore not limited to the packager constructor's initial aliases. No alias
is exported. Source privacy guards remain necessary before any media capture.

Ordinary Python/library stdout/stderr is suppressed throughout OwnerSession;
only StdIOBridge's direct fixed checkpoint-ready writes reach the action control
pipe. Exceptions produce fixed markers without arbitrary values or tracebacks.
Exit zero requires actual collection, confirmed cleanup, observed runtime end
and the owner's successful terminal reason. Every receipt still reports
`phase1_accepted=false`; only actual Root review can accept the product phase.

The selected adapter source is `integration-adapter-fix5-basics`, explicitly
vendored as `adapter/`. Its roles use the reviewed observed Home then Account
logout route. The same selected C2 module still supplies the RAM role installer,
Controller and dispatcher. This selection does not change owner authority.

The focused entry tests use synthetic files, fake SDK runners and fake lifecycle
callbacks. They verify environment isolation, exact manifest/source/run binds,
no private file indirection, installed helper hash, conservative UTC interval,
cleanup reserve, live token refusal, same C2 identity and deadline adaptation.
The deployed `--offline-tests` also runs the frozen Python component suites.
It explicitly excludes the single original adapter source-reproduction test
whose `native-fixture`/`android-alt` original source tree is not deployed to CI;
the other18 adapter runtime tests and12 focused logout tests are included. Its
31-test source suite was separately verified before vendoring. The frozen66-source suite contains216 cases: the205 Home-only cases plus11
narrow basics-capture cases. The final Fix6 source pair separately passes111
mocked base safety tests. Fresh packaged CLI results are recorded in the offline proposal receipt
OFFLINE_ENTRY_RECEIPT.json, outside the deployment manifest. Historical64/205 and provisional66/Fix5 results remain
in history and are not final-source proof.
 Node action tests/checks remain their
own explicit workflow validation; no Node result is inferred by Python tests.

This template has not been published, started a real VM, used real credentials,
made an account/API request or uploaded actual evidence during its development.
Offline tests/import checks do not close a native acceptance gate.

The selected controller source is `controller-home-diagnostic-compat`. Three new
exact deployment files are `adapter/c1_home_capture.py`,
`adapter/test_home_capture.py` and `controller/test_home_diagnostic.py`. The two
new test modules are included explicitly in the entry offline suite. Home frames
are diagnostics with their own truthful scope; they do not satisfy editor-only
C1 acceptance evidence. Existing editor capture and generic media gates remain.

All selected adapter/controller source and README files must exist before TEMP
copying. verify_deployed_layout.py validates that complete mapping, patches only
the TEMP prepare ALLOWED set, writes a fresh manifest and runs --offline-tests
with a minimal credential-free environment. It also imports the real source
closure and checks the dedicated Home mixin/role class identity without creating
a probe or VM. Root staging and prior proposals remain untouched. Root must
independently regenerate its final staging manifest and rerun these checks.
Offline BASELINE_HANDOFF.md and history preserve the recovered baseline and receipt limits; those development files are outside the deployment manifest.

The two additional basics deployment files are adapter/c1_basics_capture.py and
adapter/test_basics_capture.py. The latter is an explicit offline test module.
The final9bc1 pair hardpin preserves every reviewed Fix6 method and adds only
future deadline/IME metadata. The Java d5f48 source is unchanged. Source readiness
is distinct from native C1 completion and from Root's actual C4/C2 review.


Root staging supplies the latest workflow including QT_QPA_PLATFORM=offscreen,
encrypted installer/WebM export/cache, bounded fixture tags and current build/
fixture tests. The verifier copies those actual bytes, patches only TEMP's
ALLOWED literal to66 paths plus manifest, and never calls source_guard or native
mode. A complete source mapping is required before any copying.

## Focused field identity and OS photo cards

Before the sole focus action, the pointer target is bound twice by exact path and witness. Within the same original15-second focus window, read-only observations follow only the currently focused original Android source/window node; tree-index reflow cannot select a different field. Editable state, class, content description, hint, focus and set-text capability remain checked. The same original node may lose an in-field hint on focus; changed nonempty hints or different nodes never receive text. No focus action is repeated. A failed C1 field may report only fixed hint-transition/identity categories and a bounded observation count, never field values, paths or node identifiers.

A photo card handled by the DocumentsUI RecyclerView may be focusable without its own click listener. Such a card is admitted only within the actual document list and with the complete owned filename as the first metadata field. Preview controls, similar names, ambiguous cards and foreign packages remain excluded.

## Refused video metadata diagnostic

The frozen video-only route remains unchanged. AOSP console screen-recorder.cpp unconditionally adds a Vorbis audio stream, so the adapter explicitly supports exactly one VP9 video plus that sole native Vorbis track only after full float-PCM decoding proves every audio sample is zero. Codec, actual 540x960 dimensions, original duration limit, owned stopped file, privacy and file-stability checks remain mandatory. A 50 MB decoder output cap is a refusal, never acceptance of partial audio. The unchanged original WebM bytes are retained: no remux, transcoding, cropping or timeline change. The checkpoint producer and Root extractor independently repeat the one-video / silent-native-audio check. Audible, nonfinite, extra, foreign or unverified streams refuse. Fixed refusal metadata remains available; raw probe output and decoded audio are never exported.

Fresh disposable VM collections use independent workflow run identifiers. Retained original artifacts are never replaced by retrying an old run. An infrastructure failure before app installation creates no account fixture and does not exercise subsequent native changes.

An initial native-format refusal now retains only a fixed allowlisted condition code and bounded audio channel/sample-rate/packet-count metadata. Missing tools, read timeouts, empty/capped/misaligned decoding and nonzero PCM have distinct fixed diagnoses. The original exception, no-export decision and all validation conditions remain unchanged; arbitrary exception text, decoder output and failed media stay private.
