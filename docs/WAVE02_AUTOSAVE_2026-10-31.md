# Wave02 autosave threshold — local implementation evidence

Source: owner Wave02 handoff on 31 October 2026. This change covers only the
automatic draft checkpoint threshold. Map layout and dictation are separate.

The editor now calculates basic-data progress before its first automatic
checkpoint using the same shared property schema and field-count algorithm as
`ListingEditorDraftService::present`. Device recovery and account checkpoint
start at 50% or higher. The timer callback recalculates progress, so removing
fields before it fires prevents a new checkpoint. After automatic saving has
started, later edits keep the existing draft current even if progress drops
below 50%; no old draft is deleted. Explicit Save Draft still works below 50%.
Account and session guards remain in the editor's existing save path.

Local Flutter 3.27.3 results with CI's pinned `pubspec_overrides.yaml`:

- New `wave02_autosave_test.dart`: 3 passed, including 49/50/51 threshold,
  a fresh partial editor with no device/account write, and continued saving
  of an earlier recovery below 50%.
- `branch2_recovery_test.dart` and `wave1_experience_ui_test.dart`: 15 passed.
- Existing broker convenience recovery/autosave test: 1 passed.
- Targeted `flutter analyze`: no issues after formatting correction.
- `git diff --check`: passed.

This is synthetic/widget coverage, not a real device or UAT result. Full
Wave02 still needs the original visual/video evidence locally, native CI,
and device acceptance. The candidate source and committed pubspec lock were
not changed in this work branch.
