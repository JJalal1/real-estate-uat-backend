# Same-job controller composition

This is executable dependency-injected composition code with offline synthetic
tests. It has not started a VM, loaded real credentials, contacted UAT, run a
native journey, created Root approvals, or satisfied native acceptance gates.
Only this new directory was changed. Root owns selection/publication of the
current base, merged helper, VM, owner entry, workflow and final acceptance.

`controller.py` composes the reviewed one-shot probe, original C4/C2 V2 executor
variants, strict API fixture helper and owner kernel. `bounded_api.py` supplies
the actual fixed-origin HTTPS transport before the first bootstrap/auth request.
The controller never imports an absolute workspace path or discovers credentials.

## Wiring

Place `controller`, `integration-adapter`, its `variants`, pinned `oneshot`, and
the reviewed `aqer/scripts` on the runtime module path. Build the probe using
`make_probe_class` with the exact trusted owner grant classes. Use the SAME C2
module instance for `install_known_roles` and `Controller(c2=...)`; its private
`KnownRoleMemory` class identity matters. The controller caches those exact C4/C2
module instances for the original dispatcher.

```python
from controller import Controller

controller = Controller(
    probe=probe, c4=c4_module, c2=c2_module, dispatcher=dispatch_module,
    fixture_api_class=base.FixtureApi,
    public_reference_reader=base.read_public_reference,
    boot_runtime=boot_owned_vm_only,
    close_runtime=close_owned_vm_and_relay,
    authority_getter=lambda: owner.active_authority,
    context_getter=lambda: owner.current_context,
    work_deadline_getter=lambda: owner.work_deadline)
# Construct OwnerSession(controller=controller, ...) before invoking run().
```

The late-bound callbacks may use a holder to resolve the owner/controller
constructor cycle. They are not invoked during controller construction.
`current_context` is the owner's independent admitted context; it changes to C5
for cleanup. A stale held C4 context is not suitable for cleanup.

`boot_runtime(deadline=absolute_monotonic)` must boot ONLY the owned fresh VM.
It must not install/start APP or perform account/API work. The actual VM start
method accepts a boot-seconds cap; Root's callback must calculate it from the
remaining absolute budget and verify actual boot readiness before returning.
`close_runtime(deadline=...)` must stop only owned processes, use that exact
absolute cap, poll actual exits, and return exactly:

```python
{
    'vm_created': bool,
    'relay_created': bool,
    'vm_exit_code': int_if_created_else_None,
    'relay_exit_code': int_if_created_else_None,
    'owned_process_group_absence_observed': bool,
    'all_created_processes_observed_ended': bool,
}
```

The controller checks literal booleans and real created-process exit codes.
Missing observations cannot become zero exit codes. The fixed close callback is
reached even with an exhausted deadline so it can issue a nonblocking owned
process kill and an honest poll; no new waiting budget, UI or API work is granted.
An unknown close outcome cannot be reconstructed/retried by this controller.

The probe's actual installed-helper identity and guest UTC callbacks remain
mandatory. The controller selects no old helper SHA. Root must select/build the
reviewed merged C1-fix2/deadline/IME candidate, verify compiled/installed APK
identity and actual guest/host UTC synchronization. Capability alone is not
identity or clock proof. Fresh preflight runs during native preparation, after
actual C1 restore, and immediately before the first signed Root continuation.

## Owner callback behavior

| Method | Behavior |
|---|---|
| `prepare_runtime()` | Single VM-boot-only callback; no authority/UI/API work |
| `prepare_initial_native()` | Under the ONE existing source lease: original install/readiness, actual display configure/readback, startup, helper/UTC preflight, bounded public-reference GET and real visible native published-card match |
| `bootstrap_fixture()` | Requires actual network match first; injects bounded transport into the original FixtureApi before its normal auth/title-only bootstrap; validates actual identity/logout/readback |
| `initial_c1()` | Reopens admission after fixture0 ACK without issuing a new lease; calls original login/create/restore exactly once, requires actual case PASS, holds and clears C1-only diagnostic slots |
| `fixture_summary()` | Exact fixture UUID/tag/actor28/known pinned property ID plus baseline counts and digests only; validates original25/7 baseline identity shape |
| `snapshot()` | Pure C4 initial state, safe actual evidence, current cursor and binding; no general phase execution or UI navigation |
| `fresh_scene_matches(review,snapshot)` | Requires current cached checkpoint, actual fresh UTC, exact signed checkpoint binding, same real cursor, unchanged media and safe scene/node bindings or sparse nonimage predicates |
| `advance(review)` | Only active exact Root phase scope; exclusive attempt, exact control records0600, ONE original phase/configuration stage; progress must be observed or the controller latches |
| `finished()` | Original C2 cursor completed and actual source cleanup readback; collection only, never Phase1 acceptance |
| `uncertain()` | Permanent driver, recorder, executor, authentication or attempted-stage uncertainty; no reset |
| `quiesce_for_checkpoint()` | Known completion, no recorder, admission closed; no persistent helper-release claim |
| `stop_writers(deadline=...)` | Fixed bounded cleanup: actual known native logout if possible, admission close, APP force-stop; uncertain native completion first disposes the owned VM before API cleanup |
| `cleanup_once(deadline=...)` | Single strict route after writers stop; see below |
| `clear_private_state()` | Clear RAM role/API credentials and unlink ONLY the exact seven owned legacy review-control JSON files; keep actual report, frames, clips, proofs and separate signed ledger |

Initial SourcePlan authority is never renewed or impersonated as Root review.
Its original600-second deadline spans install/public feed, bootstrap, encrypted
fixture0 upload ACK, login/create/restore. If actual performance exceeds that
budget, the controller stops. Runtime segmentation/budget review belongs to Root;
this code never refreshes a lease to make a long run succeed.

Every public mutating callback and read-only snapshot transaction is serialized
with one reentrant, nonblocking owner lock. Concurrent calls refuse before any
second phase/transport dispatch. The same one-shot admission/latch remains on
the probe for the entire owned runtime.

## Signed review schema

Each signed advance has exact common keys:

```json
{
  "review_completed_utc": "YYYY-MM-DDTHH:MM:SSZ",
  "checkpoint_binding_sha256": "<exact snapshot stage binding>"
}
```

Add only the following cursor-specific entries:

| Current cursor/stage | Additional entry |
|---|---|
| C4 `C1_REVIEW`, `AI_REVIEW`, `APPLY_REVIEW`, `RESTORE_REVIEW` | `phase_review`: actual complete C4 remote record from `GATE_MAP.md`, including its own same actual `review_completed_utc` |
| C4 `REQUEST`, `SAVE`, `REOPEN` | None; fresh signed advance, original source guards and observed postconditions still required |
| C2 `CONFIGURE_C2` | `c1_review`, `c4_review`: the two exact original configuration proof schemas plus their actual same `review_completed_utc` |
| C2 target/observation Root gate | `phase_review`: the exact current C2 record, `executor_cursor`, actual current frame/chain/nonimage bindings and actual review UTC |
| Other C2 source stage | None; one authorized source stage and its actual original guards/postconditions |

The implementation does not populate affirmative Root flags or copy timestamps
from the current runner clock. Nested review UTC must equal the actual signed
common UTC. The original validators still enforce every affirmative flag,
frame/title/UUID relation, proposal/card selection, dialog chain and policy
condition. C2 configuration proofs require a new actual Root review at that
configuration boundary; old C1/C4 timestamps must not be refreshed automatically.

`C1_REVIEW` now prepares and reads back the exact synthetic brief, then holds at
`REQUEST` before sending it. The `REQUEST` checkpoint rechecks that exact brief
and the unchanged safe AI-sheet scene. Its separate fresh signed advance sends
the request once, waits for the actual response and captures the original AI
proposal evidence for `AI_REVIEW`. Neither segment renews its original grant or
extends120s expiry. No request, application or visual acceptance is inferred
from preparation; all four actual visual review gates remain required.

C4 filenames/hashes are supplied as the canonical sorted `[{file,sha256}]` wire
lists accepted by `ci_remote_evidence`. Actual restore duration uses its faithful
`duration_s_decimal` string. The codec alone converts these back to the original
local maps/numeric observed tuple. No nested filename keys, floats or huge JSON
string bypass is introduced into the protocol review payload.

## Read-only checkpoint boundaries

C4 safe contexts export actual guarded scene hashes and existing PNG/WebM
receipts. Initial C1 review includes its actual available safe frames and both
actual create/restore clips; later C4 reviews include the current required frame
set and exact prior proposal/restore-video bindings.

C2 visual gates call ONLY the original `_capture_rows`/`_safe_capture` read/capture
functions. They never call general `run_phase` to prepare a checkpoint. The
cached actual frame/node bindings are rechecked before signed dispatch. The
unchanged full-tree privacy predicate runs before/after capture. A blocked Sai
modal capture holds; it is never weakened. Normal financial/contact Step4 gets
no image, raw rows or UI hash. Its sparse value checks remain ephemeral.

The regular-isolation gate binds the three existing safe tab frames and the
original nonimage account witness. It exports no current account image/hash.
C2 login boundaries may follow APP force-stop; snapshots check prior known guest
state without starting APP or requesting an APP-only snapshot. Actual startup
and guest UI checks occur only inside the subsequent signed login stage.

`checkpoint_binding_sha256` hashes only the minimized checkpoint observation.
In a nonimage stage it binds cursor/fixture-owned evidence metadata and mode,
not financial/contact/profile/authentication rows. The actual sparse predicates
are run again fresh; no financial tree is hashed to manufacture a scene proof.

The source base `act()` otherwise persists selected-node hashes whenever its
driver is authenticated, including contact-step save/navigation. A controller
count-only action ledger drops every selected-node witness/private column from
that generic log while preserving actual kind/delivery/event counts. It does
not change authentication state or any original action-delivery validator.
Actual safe Root frame/scene bindings remain separate and unchanged.

## API and cleanup deadlines

The default transport fixes HTTPS to the existing UAT `/api` origin, uses default
certificate verification, follows no redirects, retries nothing, and bounds
request/response JSON. It freezes each request's exact absolute deadline and
reduces socket timeout before connection, headers/body sends and response reads.
Each controller API scope is capped by both work/cleanup deadline and the
original authority's public `monotonic_deadline`. Root/Source revocation blocks
new requests. NormalOwnerSession uses the same already-injected FixtureApi
transport. Tokens, headers, bodies, raw responses and exceptions are not stored
on controller/transport instances or exported in metrics.

The fixed direct transport has no proxy or certificate-bypass fallback. OS DNS
resolution and remote asynchronous work after a sent request are not hard
cancellable by this synchronous client. Unknown mutation completion never causes
a retry. Raw Python tracebacks can retain call locals until released; export
only fixed owner diagnostics, never arbitrary exception strings or tracebacks.

After confirmed native writers stop, one normal broker28 session freshly reads
only the original UUID/tag draft link. A promoted link additionally requires the
exact original native title. Unpromoted/absent routes use the original strict
unpromoted cleaner, which itself refuses promotion. A promoted route keeps ONE
strict original `PromotedFixtureCleanup` object through final pin and its sole
Property-first/delete-draft attempt. Normal logout200 and token-me401 are required.
An existing source cleanup helper is never reconstructed; an unknown delete
never falls back to a UUID-only delete or another attempt.

Unknown native input requires observed VM/relay exit and owned group absence
before API cleanup. API rows can be cleaned while native logout stays unproven;
the controller then returns cleanup false. C1-cleanup PASS is emitted only when
actual final row/baseline restoration, native closure and both normal API session
revocations are confirmed. A never-started native journey is distinguished from
an actually observed UI logout.

Final private clearing uses the exact allowlist: four `C4_ROOT_*` review JSON
names and three `C2_V2_ROOT_*` configuration/stage JSON names. It includes an
unconsumed stage file after preflight failure. There is no glob deletion and no
removal of actual media, report, API/source proofs or signed protocol records.

## Offline validation and pending runtime work

Run from the workspace:

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s ci-native/bridge-proposal/controller -p 'test_*.py' -v
```

Thirty-four tests passed: twelve HTTP/factory contracts and twenty-two controller
composition contracts, including a real-thread barrier proving no second phase
dispatch. Tests cover missing native network blocking seed, one-shot source
order, no general executor in snapshot, changed actual bindings, nonimage contact
checks, force-stopped login boundary, exact copied Root records, no timestamp
refresh, stage uncertainty latch, strict cleanup routing/order/same-helper/no
fallback, bounded API authority, actual exit-code requirements, count-only
action logs and exact final control-file clearing.

Root still must wire/publish the reviewed VM/entry/workflow and selected merged
helper, run the actual CI journey, review all actual encrypted evidence, issue
fresh signed commands, verify final cleanup/session/process postconditions and
make the final Phase1 acceptance decision. These offline tests close no native
acceptance gate.


---

The reviewed base documentation above is preserved verbatim. The following notes describe this NEW isolated Home compatibility extension and its additional tests.

# Narrow exclusion of C1 Home diagnostics

This NEW future controller copies the frozen controller and changes only C4
`C1_REVIEW`'s list of acceptance media. It does not broaden `_media`, alter any
input/authority/API/cleanup behavior, or create Root approvals. No current
`aqer`, old controller or native runtime was changed.

Select it with `integration-adapter-fix5-home`, whose dedicated hook emits two
possible private diagnostic files: `C1-before-add-home.png` and
`C1-restore-before-add-home.png`. A frame is excluded ONLY when it has the exact
11-key receipt, exact fixed filename/scope, official host-console PNG marker,
`authenticated_editor_only=false`, `authenticated_broker_home_only=true`,
`privacy_before_and_after=true`, `home_binding_unchanged=true`, width540/height960,
bounded actual byte count and valid SHA256 shape. Duplicate Home records refuse.

Known Home names, Home scope or the Home-only flag with malformed metadata refuse
instead of being silently discarded or relabeled. Unknown noneditor extras
still reach the original strict rejection. Home frames remain in the private
report/directory for final encrypted diagnostics; the filtering does not delete
or modify them. They are not provided as C1/C4 acceptance proof.

The `_media` function is byte-identical to the frozen controller. Calling it
directly with even a well-formed Home row still refuses the noneditor frame.
Required restored title/photo editor frames and both actual create/restore clips
remain unchanged. All original C4/C2 scene, timestamp, authority, privacy,
session-revocation, cleanup and runtime postconditions remain in force.

The original34 controller/HTTP tests plus6 narrow exclusion tests pass40 cases.
Focused cases cover legitimate exclusion and private retention, malformed and
unknown Home metadata, duplicates, direct `_media` refusal and exact `_media`
source preservation. The sole new deployment test file is
`controller/test_home_diagnostic.py`. Runtime source tests use the existing
controller test scaffold; final `adapter/` layout is supported.
