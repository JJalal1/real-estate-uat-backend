# Current State

Last updated: 2026-09-14 UTC
Current branch: `experiment/ebroker-inspired-ui-v1`
Current commit SHA: `60012ac677df7fcc79a8a30129513c22dfd28af8` (last published implementation/audit commit before this checkpoint; obtain the checkpoint's own SHA with `git log -1 --format=%H -- docs/work-progress/EBROKER_UI_REDESIGN_STATE.md` because a commit cannot contain its own hash).
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

# Current Phase

PHASE 1 — central design foundations. Implementation is next; no screen is claimed redesigned.

# Exact Last Completed Step

Verified experimental CI run `34791688437` completed successfully on `60012ac677df7fcc79a8a30129513c22dfd28af8`: all three jobs passed, 187 Flutter tests passed, APK built and uploaded as artifact `10327673645`. Baseline report records source audit findings. Draft PR #54 remains review-only.

# Next Exact Step

Implement Phase 1 by evolving existing core/theme and core/widgets: responsive Arabic compositions, scroll-safe feedback, reusable section/search/surface primitives. Add narrow-width and large-text rendered tests; run the complete experimental CI before expanding into screens.

# Files Changed

- `scripts/ui_redesign_inventory.py` — static source inventory generator.
- `scripts/verify_ui_locked_source.py` — immutable backend/Flutter boundary check.
- `docs/work-progress/EBROKER_UI_SOURCE_INVENTORY.json` — source anchors and test index.
- `docs/work-progress/EBROKER_UI_LOCKED_SOURCE.json` — locked source hashes.
- `docs/work-progress/EBROKER_UI_FEATURE_INVENTORY.md` — journey/route/screen checklist.
- `.github/workflows/experimental-ui-ci.yml` — experimental branch checks only; no deployment.
- `docs/work-progress/EBROKER_UI_BASELINE.md` — verified baseline and audit findings.
- This checkpoint.

# Screens Completed

None. Existing UI is untouched.

# Screens Remaining

All 71 presentation files and router error presentation. See the per-file checklist in `EBROKER_UI_FEATURE_INVENTORY.md`; this includes secondary/internal screens and modal/forms, not just top-level routes.

# Tests Last Run

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

# Known Issues

- Architecture Debt: several project overview/roadmap docs predate live financial and agreement implementation. Current stable source + tests + this task override stale roadmap descriptions.
- Architecture Debt: legacy phase workflows reference the previous non-Frankfurt endpoint. Do not run those workflows. Dedicated experimental CI reuses the current Frankfurt APK gate.
- Environment: Flutter was not preinstalled. Official SDK archive/release-index requests returned 404; the official 3.27.3 Git clone succeeded and engine Dart downloaded. Dart VM execution then failed retrieving stack bounds in this workspace. Do not weaken sandbox controls to work around this; use authorized GitHub Actions.
- Inventory limitation: static anchors do not prove every callback/state has been manually reviewed or rendered. Review the complete affected file and its tests before each redesign commit.
- Architecture Debt (confirmed): `ProjectsScreen` contains static `_ProjectData` and is referenced only in its own file; accepted IA tests explicitly keep projects out of active navigation. Preserve it as an unreachable legacy file, do not promote it or claim a connected redesign. Real developments use the existing repository.
- Test Coverage Debt: startup navigation layout fixtures include historical manager/GM labels; source-contract tests check the current labels. Preserve stress fixtures and add actual current-role rendered tests during role review.
- UI Bug candidates from source audit: property-detail similar-card list has fixed height 340; map result/selection cards use fixed heights and compact 32px actions; generic centered feedback is not scrollable. Address with responsive presentation and rendered tests in corresponding phases.
- Delivery environment: direct `git push` has no local credential. GitHub connector create-tree/create-commit/non-forced update-ref succeeded. Local tree was verified identical, then aligned with the published SHA via fetch + soft reset. Do not request or expose a token.
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
