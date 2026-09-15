# Experimental UI baseline

Source: `46b8fed8fd119b223d4a1e67312d38ff9429e569`.
Audit/CI head: `60012ac677df7fcc79a8a30129513c22dfd28af8`.
Fresh run: https://github.com/JJalal1/real-estate-uat-backend/actions/runs/34791688437
Prior exact-source success: https://github.com/JJalal1/real-estate-uat-backend/actions/runs/34788153227

## Source inventory

- 141 Flutter Dart source files; 71 presentation files with secondary screens/modal widgets included.
- 35 declared GoRouter paths, plus imperative routes indexed in the source inventory.
- 54 existing Flutter test files.
- 346 immutable backend/domain/repository/router/network/session/platform file fingerprints.
- All three accepted mobile source hashes match their existing build gate.
- No application source, API, database schema, cloud configuration, role, or business rule changed during this audit.

The JSON index preserves every source file's hash and identified CTA/form/state/dialog/permission/provider/API anchors. The Markdown checklist maps journeys, personas, routes and all presentation files. It is a preservation checklist, not a claim that runtime visual QA has already occurred.

## Fresh automated results (2026-09-14 UTC)

| Check | Result | Evidence |
| --- | --- | --- |
| Laravel regression | PASS: 172 passed, 1 existing SQLite/PostGIS skip; 1779 assertions | Job 103816989128 |
| PostgreSQL 17/PostGIS full migration chain | PASS | Job 103816989238 |
| PostgreSQL schema/security/agreements/Sai/preferences | PASS: 10 tests; 271 assertions | Job 103816989238 |
| Explicit PostGIS overlap regression | PASS: 1 test; 6 assertions | Job 103816989238; runs the spatial case omitted under SQLite |
| Flutter 3.27.3 dependency resolution | PASS | Job 103817096150 |
| Flutter analyze | PASS | Job 103817096150 |
| Cloud-readiness tests | PASS | Job 103817096150 |
| Full existing Flutter suite | PASS: 187 tests | Job 103817096150 |
| Compile-time UAT guard | PASS, Frankfurt endpoint | Job 103817096150 |
| Live UAT health | PASS | Job 103817096150 |
| 40 concurrent nearby-property reads, concurrency 20 | PASS | Job 103817096150 |
| Baseline release APK | PASS: built and uploaded (45.8 MB) | Job 103817096150 |
| Locked-source verifier and git diff check | PASS locally and in CI | Audit branch |

## Execution environment

Flutter/PHP/Android SDK/emulator were not preinstalled in Work. Flutter's official `3.27.3` source was cloned separately under the transient toolchain directory. Its Dart 3.6.1 engine SDK downloaded, but starting the VM to bootstrap Flutter failed with `Failed to retrieve stack bounds`. The version command alone succeeds and is not evidence that analyzer/tests can run. No sandbox permissions or runtime code were weakened. Fresh GitHub Actions supplies the actual baseline execution.

Direct Git push lacks a local credential. Publishing uses the authorized GitHub connector's Git tree/commit/ref APIs. The local and remote tree hashes are checked for equality before aligning the local branch with the resulting remote commit. Never force-push or update a stable ref.

## Presentation findings to address

1. Discovery is currently map-first with map/list state preserved locally; changing its default would be a product/navigation behavior change. Improve the existing discovery surface and cards without silently changing the initial mode.
2. Existing compact map/property cards use fixed heights and small action areas. Rebuild their presentation with content-driven sizing while retaining all map/favorite/details callbacks.
3. Similar properties use a fixed 340px horizontal viewport; large Arabic text can exceed it. Fix in the property-details phase with rendered width/text-scale coverage.
4. Centered loading/error/empty primitives have no internal scrolling. Fix in the foundation phase without hiding labels or disabling text scaling.
5. Most business mutation functions live in screen State classes. Modify only widget composition and preserve those methods, conditions, provider reads and payloads.
6. The current theme already has semantic status colors, spacing, radii, motion and a bundled Arabic font. Evolve it and its shared components, rather than introduce a parallel theme.

## Existing architecture and coverage debt

- Some roadmap/overview docs describe older states. Current code includes agreements and Financial V1; current tests and stable source govern those journeys.
- Legacy CI files reference the older UAT URL. The experimental gate derives from the current Frankfurt build workflow; no old endpoint is executed.
- `ProjectsScreen` is an unreachable legacy placeholder, referenced only within its own file. Existing IA tests intentionally exclude it. It is retained, not exposed or relabeled as real API data. Real development screens have their own repository.
- Startup navigation layout tests contain historical labels; separate source-contract tests enforce current GM labels. Add current-persona rendered coverage while preserving useful existing long-label stress tests.
- Static inventories and source-string contract tests do not replace complete per-screen runtime/visual review. Each screen remains open in the checklist until its definition of done is met.

## Reference direction

Eight Google Play screenshots were inspected in the browser: login, home, property details, listing rows, categories, subscription cards, location sheet, and map. Adopt image hierarchy, section spacing, rounded cards and clear contextual actions. Keep the original Arabic name/green identity and use only actual project fields. Do not introduce subscriptions, paid featuring, mortgage UI, reference logos/photos, or unsupported chat/attachment features.

## Required next gates

Baseline run completed successfully. Validate reusable presentation components at 320/360/412/600px and Arabic text scales, retain every current test and source guard, and capture rendered evidence from isolated widget tests if Android emulation remains unavailable. Isolated test fixtures must never enter application runtime data.

Baseline APK artifact: `10327673645` / `real-estate-experimental-ui-apk-1`, retained until 2026-09-28. This is the unchanged baseline application, not the redesigned deliverable. The artifact ZIP digest is not the APK digest; `SHA256.txt` inside the archive contains the APK checksum.
