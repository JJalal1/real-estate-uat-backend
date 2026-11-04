# C2 logout postcondition correction

This isolated replacement adapter changes only the C2 native-role logout
postcondition and its fixed safe error classification. It changes no original
source, old frozen adapter, controller runtime, guest input/deadline code,
credentials, native VM, API or external service. These offline tests are not
native logout, server revocation, Root review or Phase1 acceptance evidence.

The actual application resets the selected shell page to index0 when account
scope changes (`app_shell_screen.dart`, accountScope block104–112). A null user
uses the default normal shell, whose page0 is GuestMarketplace and whose four
footer labels are `العقارات`, `الرسائل`, `إعلاناتي`, `حسابي`. The Home search hint
is exactly `ابحث عن عقار أو منطقة…`; its category header is `ماذا تبحث عنه؟`.
The previous role helper incorrectly waited for the Account login gate directly
after tapping Logout.

The corrected ordinary native sequence is:

1. Keep the existing known-role/recorder preconditions and initial Account tap.
2. Set count-only authentication handling, then deliver ONE existing Logout tap.
3. Read only until visible APP rows contain all four normal footer labels and
   one exact Home anchor. Old broker/support navigation, Logout and auth controls
   refuse the Home predicate. Hidden/foreign anchors do not count. The footer
   alone is insufficient, including for regular users who share it with guests.
4. Deliver ONE post-logout Account tap (`seek=False`).
5. Preserve the actual visible APP Login-present/Logout-absent/auth-absent guest
   check before clearing native actor uncertainty.

There is no repeated Logout, alternate navigation, retry, reauthentication,
capture, witness hash, app-storage read or server call. The polling deadline is
only a bounded read wait; it does not refresh the original signed input grant.
The post-Home Account tap still uses the same per-input admission/deadline
enforcement. An expired grant or unknown result blocks continuation. The native
UI logout receipt explicitly continues to deny server-token-revocation proof.

`build_ci_variants.py` reproduces the entire same-layout package from the exact
original pinned source files. `variants/VARIANT_MANIFEST.json` records every
original/result SHA256 and the previous UTC role variant SHA. All other generated
Python variants, the one-shot probe adapter and remote evidence codec are
byte-identical to the frozen `integration-adapter` package. Tests also fence the
unchanged role-module AST outside the reviewed logout helper/error classification
and the two added fixed Home constants. The three active remote-UTC validation
sites, original media/privacy guards, strict promoted cleanup, deadline/admission
and no-replay behavior are unchanged.

Root must select this directory as the adapter source when assembling the final
runtime. Import the NEW C2 module once, use its `roles.install_known_roles` when
constructing the probe, and pass that SAME C2 module to the unchanged Controller.
The Controller caches those exact module instances for dispatch. Mixing an old
`KnownRoleMemory` class with the new executor is unsupported. No controller
rewrite is needed. Root independently selects/builds the current reviewed merged
guest helper; this correction pins or selects no stale helper APK.

Run the local source checks with:

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s ci-native/bridge-proposal/integration-adapter-logout-fix -p 'test_*.py' -v
```

All31 tests pass: the existing19 adapter/evidence contracts plus12 focused logout
contracts. The focused cases cover all three roles and both exact anchors,
regular's identical footer, hidden/foreign/missing anchors or footer items,
stale role/auth controls, delayed read-only Home observation, no repeated input
after expiry, final visible guest gate, raw-error redaction and source/hash
fences. A separate packaged-layout run validates these12 focused cases and the
unchanged34 controller/HTTP tests against this new adapter instance.

The real broker/support/regular logout behavior, signed-stage runtime budget and
unchanged privacy predicates still require actual native execution. A successful
synthetic test never substitutes for those observations.


---

The reviewed base documentation above is preserved verbatim. The following notes describe this NEW isolated Home compatibility extension and its additional tests.

# Fix5 C1 Home diagnostic compatibility

This NEW future adapter copies the frozen logout-fix package and adds one
dedicated ordinary C1 Home capture hook. It changes no current `aqer`, old frozen
adapter, guest helper, Root approval, API or native runtime. No native capture or
acceptance is claimed by these synthetic tests.

The paired future Base is `guest-deadline-fix5/probe_phase1_native_account.py`,
SHA256 `35fb0470b97c1e25b68811ce92f2d9db39a7c4a64d64b3a64996bb0e3d464816`.
Its Java input source remains `d5f48e475c805a4a03020b06ffa375351f51b1bbfeb710712591745cf12da5fc`.
Root must explicitly select/build/verify that pair. This adapter does not infer
installed APK identity or guest-clock synchronization from these source hashes.

The exact Base API is `capture_initial_broker_home()` with scope/name helper
`initial_home_capture_name()` and pure `broker_home_ready(rows)`. The Base invokes
the hook after its initial broker Home check and before stabilizing/delivering
the one Add action. `C1-photo-save` maps to `C1-before-add-home.png`;
`C1-force-stop-restore` maps to `C1-restore-before-add-home.png`.

`c1_home_capture.py` implements ONLY this dedicated hook. The factory adds its
mixin before the existing HostConsoleCaptureMixin. The frozen editor
`safe_capture`, `_capture_guard`, PNG CRC/540x960 validator, full mounted-tree
privacy predicate and all input/deadline/admission code remain unchanged.
The normal editor path still refuses Home and still stamps only editor proof.

Before AND after the actual official emulator-console screenshot, the new hook
requires the original live SOURCE_PLAN_ONLY authority, one of the two exact C1
cases, authentication, no recorder, healthy admission, the full mounted APP
privacy predicate, Base broker Home guard, and visible exact Home header/search
plus all broker footer labels. Contact controls below the viewport still block;
visible auth/profile/private aliases block. Hidden/foreign/ambiguous Home anchors
cannot satisfy the visible Home proof. The six fixed public Home anchors have
the same path/witness/bounds before and after capture. No raw tree or binding is
saved. There is no C2/C4/Root-target capture route or UI navigation in this hook.

Only `emu screenrecord screenshot` is used. Its one actual PNG is validated by
the unchanged frozen CRC/dimension validator. Output uses an exclusive nofollow
0600 file; duplicates, dangling symlinks, multiple console files, bad CRC/dimensions,
private transitions or changed Home bindings refuse instead of overwriting or
exporting a frame. A final Add target lease is obtained separately by Base Fix5;
the diagnostic never substitutes for target stability or input delivery proof.

Successful receipts contain exactly:

```text
file, bytes, sha256, width=540, height=960,
capture=official_emulator_console_host_png,
authenticated_editor_only=false,
authenticated_broker_home_only=true,
capture_scope=authenticated_broker_marketplace_before_add,
privacy_before_and_after=true,
home_binding_unchanged=true
```

The marker describes actual host-console PNG provenance; guest screencaps are
never relabeled. These Home images are private diagnostics, not C1/C4 acceptance
frames. Select `controller-home-diagnostic-compat` together with this adapter:
it excludes only these exact well-formed diagnostic receipts from C4's initial
all-frame selection while keeping the editor-only `_media` policy unchanged.
The actual diagnostic files/records remain available for final encryption.

The generated `variants` and their manifest remain byte-identical to logout-fix,
including C2's one-Logout→observed Guest Home→one Account correction. The source
builder is unchanged and reproduces those exact pinned variants. Use the SAME
newly selected C2 module for the RAM role installer and Controller, as before.
The additional flat deployment files are `adapter/c1_home_capture.py` and
`adapter/test_home_capture.py`; `ci_probe_adapter.py` changes only its import and
factory MRO. `test_logout_home.py` moves the old whole-probe hash fence to the new
AST-preservation test because the dedicated mixin is intentionally added.

Offline checks pass43 tests: prior19 adapter/evidence,12 logout, and12 dedicated
Home cases. They check actual synthetic console bytes/provenance, both fixed
names, full hidden-contact and visible auth/profile/alias rejection, after-frame
privacy/identity change, scope/lease/recorder restrictions, ambiguous anchors,
bad CRC/dimensions, duplicate files/symlinks, unchanged editor refusal and exact
old adapter AST after removing only the reviewed mixin/import addition.
Runtime performance, actual Home pixels and all acceptance gates remain separate.


---

# Additional narrow loaded-basics compatibility

This final isolated adapter source is `integration-adapter-fix5-basics`. The Home
package documentation above remains preserved. Add `c1_basics_capture.py` and
`test_basics_capture.py`; the factory only adds that dedicated mixin import/MRO.
The Home hook, frozen HostConsoleCaptureMixin, generic editor `_capture_guard`,
all variants, role logout, deadlines/admission and controller remain unchanged.
Select the unchanged `controller-home-diagnostic-compat` (runtime SHA256
`9d6be413b0a3381bae65ece6054cefd6de1bf1aaa78d9b3929a40ecec67c9e56`).

The source compatibility issue is concrete: Base.capture_basic_editor can capture
loaded purpose/type basics before the title is visible. The frozen generic Host
editor guard admits title/spec/location/photo anchors, so it can correctly refuse
that separate basics state. This is a source compatibility correction, not a new
claim about an observed native failure.

The new mixin overrides ONLY `capture_basic_editor('C1-basic-editor')`. All other
names, including `C1-owned-editor-title`, delegate original arguments/results to
super unchanged, retaining visible-title/identity checks and sequencing. The
narrow branch requires authenticated `C1-photo-save`, the SAME active
SOURCE_PLAN_ONLY lease and no recorder. Before AND after the actual official
console screenshot it checks full mounted-tree privacy, fresh VISIBLE
basic_editor_loaded, exact Add/1/4/purpose/type anchors and unchanged unique
public path/witness/bounds. It navigates nowhere and dispatches no UI input.

The one fixed output `C1-basic-editor.png` is exclusive/nofollow0600, one actual
PNG with the unchanged CRC/540x960 validator. Duplicate files/symlinks, hidden or
foreign/ambiguous anchors, private transitions, changed binding and invalid PNG
output refuse. It records authenticated_editor_only=true with truthful scope
`authenticated_c1_loaded_basics_before_title`, privacy/binding facts, and explicit
`title_identity_proved=false`, `fixture_uuid_identity_proved=false`. A basics
state image does not establish the draft title or UUID. The existing final
required restored title/photo and both actual clips remain mandatory.

The source hook API baseline was frozen at the Fix5 probe35fb0470 above. Root's
entry independently pins the final selected future probe, including any reviewed
startup-only rebase; this adapter never selects a stale probe or installed APK
itself. Actual helper identity, guest UTC sync and native acceptance remain the
owner's runtime obligations.

Source checks pass54 tests (the preserved43 plus11 focused basics cases). The
focused cases cover truthful provenance/no title or UUID claim, original owned
title delegation, contact/auth/profile/alias privacy, after-capture transitions,
C1/source/recorder scope, missing/hidden/foreign/ambiguous anchors, original loaded
context, bad CRC/dimensions, duplicate/symlink protection and unchanged generic
editor refusal with no capture input. A fresh packaged adapter layout passes35
Home/logout/basics tests plus the unchanged40 controller tests. The provisional
entry closure grows from64 to66 files, adding only `adapter/c1_basics_capture.py`
and `adapter/test_basics_capture.py`; updated factory/test hashes must be pinned.
None of these offline checks closes native or Root acceptance gates.
