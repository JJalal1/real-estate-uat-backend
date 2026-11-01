# Wave02 autosave threshold — local implementation evidence

Source: owner Wave02 handoff on 31 October 2026. This change covers only the
automatic draft checkpoint threshold. Map layout and dictation are separate.

The editor now calculates basic-data progress before its first automatic
checkpoint using the same shared property schema and field-count algorithm as
`ListingEditorDraftService::present`. Device recovery and account checkpoint
start at 50% or higher. The timer callback and each automatic device/account
write recalculate progress, so removing fields before the timer fires prevents
a new checkpoint. Falling below 50% stops new automatic writes even for an
earlier saved draft; the earlier version is retained. Explicit Save Draft still
works below 50%.
Account and session guards remain in the editor's existing save path.

Local Flutter 3.27.3 results with CI's pinned `pubspec_overrides.yaml`:

- New `wave02_autosave_test.dart`: 13 passed, covering 49/50/51 threshold, a
  fresh partial editor, account switch, a queued timer followed by a drop
  below 50%, writes beginning above the threshold then stopping below it,
  earlier device and account drafts retained without another write, and
  explicit exit save below the threshold. The tests also cover central
  completion for all eight listing types, a manual Save queued while automatic
  reconciliation waits, and upload/remove conflict retries after a drop. A
  second conflict test advances the server revision while the user requests a
  manual Save; the editor adopts that revision without retrying the automatic
  upload, then completes the explicit Save.
- `branch2_recovery_test.dart` and `wave1_experience_ui_test.dart`: 15 passed.
- Three related photo upload, lost-response, and removal regressions: passed.
- Existing broker convenience recovery/autosave test: 1 passed.
- Targeted `flutter analyze`: no issues after formatting correction.
- `git diff --check`: passed.

The full `user_work_media_test.dart` run passed 16 cases and failed two photo
case teardowns when Windows held a temporary file open. The same focused photo
case fails on the unchanged `03f77c1` source in the separate test sandbox,
with identical file hashes for the source and test. This does not verify those
two photo cases as passing; it identifies a pre-existing local test/file-lock
failure that is independent of the threshold change.

This is synthetic/widget coverage, not a real device or UAT result. Full
Wave02 still needs the original visual/video evidence locally, native CI,
and device acceptance. The candidate source and committed pubspec lock were
not changed in this work branch.
