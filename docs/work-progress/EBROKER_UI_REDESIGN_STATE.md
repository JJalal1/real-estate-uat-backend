# Current State

Last updated: 2026-09-14 UTC
Current branch: `experiment/ebroker-inspired-ui-v1`
Current commit SHA: `fea1b42c7c202706aba63ebb0417e6285b310bd0` (last published implementation/audit commit before this checkpoint; obtain the checkpoint's own SHA with `git log -1 --format=%H -- docs/work-progress/EBROKER_UI_REDESIGN_STATE.md` because a commit cannot contain its own hash).
Latest stable source SHA: `46b8fed8fd119b223d4a1e67312d38ff9429e569`, verified directly against GitHub on 2026-09-13 at task start.
Initial main SHA: `5b2c226aca467fc8ec392782d6e2a1a0d7271bb6`.

# Mission

Comprehensively redesign the existing Arabic/Yemeni Flutter application, using eBroker only as a visual reference, with an original identity. Preserve every existing journey, role, state, validation, API, and backend business/security boundary. Work exclusively on this experimental branch; never merge or deploy without a later explicit instruction.

# Locked Rules

- `main` and `audit/system-stabilization` must not be modified or force-pushed.
- Backend, repositories, models, API client, auth/session/media access, routes and deep-link logic remain authoritative and unchanged. Baseline hashes are captured in `EBROKER_UI_LOCKED_SOURCE.json`.
- Preserve Property Identity V2, duplicates, representation claims, KYC camera-only selfie, shared support claim ownership, Sai policy, Financial V1, manual payments, confirmations, holds, agreements, attestations, disputes, and exact role permissions.
- GM tabs: الرئيسية، السوق، الإدارة، التقارير، حسابي — exactly five. Do not replace existing persona navigation with eBroker navigation.
- Public published browsing remains anonymous; private journeys preserve auth gates.
- No demo fields/data, eBroker branding/assets, paid promotion, new product behavior, or production resources/signing.
- Cloud checks use only `https://real-estate-uat-api-frankfurt.onrender.com/api`, copied from the stable APK workflow. No deployment is authorized by this redesign.
- Do not weaken tests, accepted-source guards, validation, or security assertions.

# Completed Phases

PHASE 0 completed at source/automated-baseline level (runtime per-screen review remains a redesign gate):
- Verified repository access and live stable HEAD; cloned independent workspace and created experimental branch remotely and locally.
- Read repository operating contract and architecture/business/workflow/security/runbook/decision/task documents.
- Read router, app shell, auth gates/controller, API client, design foundation and representative current contract tests.
- Captured all 141 Dart source files (71 presentation files), 98 test/fixture files, and source anchors for actions/forms/states/navigation/permissions/APIs.
- Captured immutable hashes for 346 backend and Flutter boundary files.
- Inspected all eight Google Play screenshots in the browser; located official WRTeam additional visual references.

PHASE 1 design foundations completed: reusable compositions, responsive feedback/headings/facts, Arabic typography and semantic colors preserved, reduced motion, 11 new widget cases, corrected eight-image visual QA. Application source at `3630b94` passed complete CI/APK. Test-only correction at `1993b96` passed analyze/tests and produced inspected corrected screenshots; its full CI/APK rebuild succeeded.

# Current Phase

PHASE 2 — map discovery entry and isolated Android package passed CI at `f8dba503` (215 Flutter tests). Follow-up feedback and contrast fixes are being validated. Added current manager/GM label stress cases while preserving prior tests. Map/list cards and sheets remain in Phase 3; no complete screen is claimed redesigned yet.

# Exact Last Completed Step

Run `34910573934` verified SDK repair, analyze, backend and rendered tonal contrast. One sliver retry test failed because its synthetic tap occurred before a frame applied ensureVisible scroll offsets (tap y=623 outside 280px viewport). Added frame settling after scrolling in foundation/discovery interaction tests; original callback assertions remain intact. Phase 3 card work is saved in local stash `phase3: property card presentation in progress` and is not published.

Resumed from remote `f8dba503` after Work restored an older local checkout. Preserved old local notes in a named stash. Recovered the exact three-file sliver feedback fix from Git tree `bc2ac513` with blob hash checks and published it as `4b2cab0206e5acd9734325536c66b351f46c9a5c`. Verified prior Phase 2 CI/APK success and inspected four discovery screenshots. The fresh run `34910136499` failed before Flutter setup because sdkmanager could not resolve retired package `tools`; backend jobs passed.

# Next Exact Step

Verify fresh CI after the separate SDK setup and tonal contrast commits; require the sliver retry test and rendered tonal contrast test to pass, and inspect replacement discovery images. Then proceed to marketplace property cards and responsive list presentation. Do not repeat Phase 0/1 or replace the experimental base.

# Files Changed

- `scripts/ui_redesign_inventory.py` — static source inventory generator.
- `scripts/verify_ui_locked_source.py` — immutable backend/Flutter boundary check.
- `docs/work-progress/EBROKER_UI_SOURCE_INVENTORY.json` — source anchors and test index.
- `docs/work-progress/EBROKER_UI_LOCKED_SOURCE.json` — locked source hashes.
- `docs/work-progress/EBROKER_UI_FEATURE_INVENTORY.md` — journey/route/screen checklist.
- `.github/workflows/experimental-ui-ci.yml` — experimental branch checks only; no deployment.
- `docs/work-progress/EBROKER_UI_BASELINE.md` — verified baseline and audit findings.
- `mobile_app/lib/core/design/` — shared facade and responsive page/section/search/action/identity compositions.
- `mobile_app/lib/core/theme/app_tokens.dart` — centralized foundation dimensions.
- `mobile_app/lib/core/widgets/app_components.dart` — responsive headings/facts, scroll-safe feedback, reduced motion.
- `mobile_app/test/experimental_design_foundation_test.dart` — 11 rendering/interaction cases plus CI screenshots.
- `docs/work-progress/EBROKER_UI_DESIGN_SYSTEM.md` — component responsibilities and verification.
- `mobile_app/lib/features/map/presentation/discovery_filter_panel.dart` — pure discovery controls; same values/order/callback contract.
- `mobile_app/lib/features/map/presentation/map_screen.dart` — panel composition and flow-positioned area chip only.
- `mobile_app/test/experimental_discovery_entry_test.dart` — controls/gesture wiring/RTL rendering coverage.
- `mobile_app/test/startup_navigation_layout_test.dart` — current manager and GM labels added to existing stress tests.
- `mobile_app/android/app/build.gradle` and `AndroidManifest.xml` — separate installable experimental identity; unchanged native namespace and permissions.
- Experimental CI verifies compiled package, Arabic launcher label and native activity before upload.
- `mobile_app/test/support/capture_design.dart` — real shadow rendering for captured evidence, with test debug globals restored before invariant checks.
- This checkpoint.

# Screens Completed

None. Shared foundations changed; screen composition phases remain open.

# Screens Remaining

All 71 presentation files and router error presentation. See the per-file checklist in `EBROKER_UI_FEATURE_INVENTORY.md`; this includes secondary/internal screens and modal/forms, not just top-level routes.

# Tests Last Run

- Run `34910573934`, SHA `fea1b42`: backend/PostGIS, pub get/analyze, cloud-readiness and tonal contrast PASS; full Flutter suite failed only sliver retry interaction; APK not built. Scroll-before-tap test scheduling correction pending CI.

Date: 2026-09-14 UTC. Source tested: `60012ac677df7fcc79a8a30129513c22dfd28af8` (application code identical to stable `46b8fed8fd119b223d4a1e67312d38ff9429e569`).
- Repository status/branch/log: clean source; experimental branch at verified stable HEAD before audit files.
- Existing `git hash-object` guards: all three match (API client, router, services).
- Inventory generation: PASS (141 Dart files; 71 presentation files; 346 locked files).
- Local Flutter 3.27.3 bootstrap: BLOCKED during Dart VM startup with `Failed to retrieve stack bounds`; `dart --version` works but is not a test result.
- Fresh experimental CI `34791688437`, SHA `60012ac677df7fcc79a8a30129513c22dfd28af8`: `flutter pub get`, `flutter analyze`, cloud-readiness tests, full existing Flutter suite (187 tests), Frankfurt compile-time guard, live health and 40 concurrent nearby reads PASS. Release APK build/upload PASS.
- Laravel full regression: 172 passed, 1 existing PostGIS-only skip under SQLite; 1779 assertions. PostgreSQL/PostGIS: 10 passed / 271 assertions, plus explicit spatial overlap regression 1 passed / 6 assertions. No skip/expectation was altered.
- Independent prior stable-SHA CI: `34788153227` / Build UAT Android APK #55 SUCCESS, including all analysis/tests/build and Frankfurt health/load.
- Local PHP/Composer: unavailable; disposable CI Laravel/PostgreSQL checks are required.
- Baseline APK: PASS, 45.8 MB; artifact `10327673645`. Android visual QA not yet run.
- Phase 1 CI `34882892445` / `3630b94`: analyze and all Flutter tests PASS; complete run SUCCESS; 198 Flutter tests and APK passed.
- Phase 2 CI `34884689076` / `f8dba503`: pub get/analyze, 215 Flutter tests, backend/PostGIS, Frankfurt guards/health/load and APK PASS; isolated package/Arabic label/native activity verified.
- Sliver fix CI `34910136499` / `4b2cab0`: backend PASS; Flutter NOT RUN due to Android SDK setup failure.
- Phase 1 local: `git diff --check` and locked-source verifier PASS. Flutter execution remains unavailable locally; CI now passed for application implementation; see above.

# Known Issues

- Architecture Debt: several project overview/roadmap docs predate live financial and agreement implementation. Current stable source + tests + this task override stale roadmap descriptions.
- Architecture Debt: legacy phase workflows reference the previous non-Frankfurt endpoint. Do not run those workflows. Dedicated experimental CI reuses the current Frankfurt APK gate.
- Environment: Flutter was not preinstalled. Official SDK archive/release-index requests returned 404; the official 3.27.3 Git clone succeeded and engine Dart downloaded. Dart VM execution then failed retrieving stack bounds in this workspace. Do not weaken sandbox controls to work around this; use authorized GitHub Actions.
- Inventory limitation: static anchors do not prove every callback/state has been manually reviewed or rendered. Review the complete affected file and its tests before each redesign commit.
- Architecture Debt (confirmed): `ProjectsScreen` contains static `_ProjectData` and is referenced only in its own file; accepted IA tests explicitly keep projects out of active navigation. Preserve it as an unreachable legacy file, do not promote it or claim a connected redesign. Real developments use the existing repository.
- Test Coverage Debt: startup navigation layout fixtures include historical manager/GM labels; source-contract tests check the current labels. Preserve stress fixtures and add actual current-role rendered tests during role review.
- UI Bug candidates from source audit: property-detail similar-card list has fixed height 340; map result/selection cards use fixed heights and compact 32px actions; generic centered feedback is not scrollable. Address with responsive presentation and rendered tests in corresponding phases.
- Delivery environment: direct `git push` has no local credential. GitHub connector create-tree/create-commit/non-forced update-ref succeeded. Local tree was verified identical, then aligned with the published SHA via fetch + soft reset. Do not request or expose a token.
- Visual QA harness issue RESOLVED: corrected artifact `10364505958` inspected at all four widths / both scales. Supersedes square-glyph artifact `10363582427`. These remain isolated component images, not authenticated Android screen evidence.
- Earlier Phase 0/1 APKs use the baseline UAT application ID. The Phase 2 packaging commit changes only experimental application ID and launcher label; compiled package verification passed in run `34884689076`. Namespace/native channels/deep-link scheme/permissions/debug signing stay unchanged, and file-provider authority follows packageName dynamically.
- Phase 2 map preview/cards/bottom bars retain their prior sizing until Phase 3; do not claim the entire discovery screen complete based on the new top panel alone.
- Regression discovered by source review: LayoutBuilder in feedback is incompatible with SliverFillRemaining(hasScrollBody:false) intrinsic sizing used by Messages and My Listings. Replaced it with intrinsic-safe centered scrolling; added a rendered sliver/retry test and retained a meaningful no-competing-inner-scroll assertion. Fresh CI pending.
- CI Environment: run `34910136499` failed in Android setup before Flutter because the default legacy `tools` package is unavailable. Experimental workflow now explicitly requests supported `platform-tools`; SDK command-line setup and every analyzer/test/APK gate remain enabled.
- UI Bug: visual inspection found white tonal-button text on a pale container, inherited from the global FilledButtonTheme. An explicit tonal foreground and rendered contrast regression are implemented in a separate change; fresh CI pending.
- No WHY_BACKEND_CHANGE_IS_NEEDED: none identified; backend changes are not planned.

# Decisions

- Reuse and evolve `core/theme` and `core/widgets`; avoid a parallel theme system. A central `core/design` facade/compositions may build on these foundations.
- Keep the existing original Arabic name `عقارات حولك`, locally bundled NotoSansArabic, semantic status meanings, and green identity; reference layout quality rather than copying eBroker's teal branding.
- Keep all business mutations and providers in place when restructuring widget composition.
- Treat static source contracts as important regression gates; only update purely visual assertions when the replacement has equivalent or stronger coverage and the design change requires it.
- New audit numbering (redesign Phase 0–12) is separate from old product roadmap phase numbering.

# Do Not Redo

- Do not recreate or reset the experimental branch.
- Do not regenerate the captured inventory/locked-source manifests from changed UI; they describe stable source.
- Do not replace the verified stable base with an old ZIP, `main`, or an integration branch.
- Do not import reference images into app assets.

# Visual Reference Notes

Google Play: https://play.google.com/store/apps/details?id=com.ebroker.wrteam

Inspected all eight current screenshots: login, home discovery, property details, most-viewed listing rows, category grid, subscription cards, location bottom sheet, map. Observed large property imagery, clear search entry, rounded cards, small purposeful badges, distinct price/title/location hierarchy, contextual bottom actions and restrained whitespace. Subscription/mortgage/advertising features are not product requirements and must not be introduced.

Official supplementary source: https://www.marketplace.wrteam.in/products/ebroker-real-estate-management-software — public links include live chat, quick property add, property management, verified agents, and home sections. Supplementary chat/create/manage image retrieval failed through the web image host; those images are not claimed inspected. Play screenshots do not establish chat/profile/loading/animation behavior; do not claim those were observed there.

# Resume Instructions

Draft PR: https://github.com/JJalal1/real-estate-uat-backend/pull/54
Experimental CI: https://github.com/JJalal1/real-estate-uat-backend/actions/runs/34791688437

1. Read this file, `AGENTS.md`, then `git status`, `git branch --show-current`, `git log -5 --oneline` and remote experimental HEAD.
2. Continue only on `experiment/ebroker-inspired-ui-v1`; preserve unrelated user changes.
3. Read the latest CI for the actual tested SHA, not an older successful artifact. Fix any baseline regression before UI expansion.
4. Follow Next Exact Step. Read affected inventory anchors plus complete implementation/tests. Keep source/model/repository/backend boundaries intact.
5. After each logical part: verify, update this checkpoint, commit, push and monitor phase CI. Never claim a screen complete without its rendering/RTL/state/action/API/permission requirements being checked.
6. Session end: preserve valid work in commits, push only this branch, record exact last tested and next steps, leave a clean working tree. Never merge, deploy, or access Production.
