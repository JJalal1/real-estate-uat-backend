# Current State

Last updated: 2026-09-20 UTC
Current branch: `experiment/ebroker-inspired-ui-v1`
Current commit SHA: `8aab16d97386ed1977e848c81cfef70e3e3915c9` (last published implementation/audit commit before this checkpoint; obtain the checkpoint's own SHA with `git log -1 --format=%H -- docs/work-progress/EBROKER_UI_REDESIGN_STATE.md` because a commit cannot contain its own hash).
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

PHASE 5 — responsive listing editor. Discovery, saved searches, comparison and property details presentation have passed automated regression; per-screen authenticated Android acceptance remains open.

# Exact Last Completed Step

Comparison commit `18677a960ef557542723bd185bb5b39e037012c3` passed Experimental UI `35482673515` and companion `35482675141`: analyze, complete Flutter suites, backend/PostGIS, Frankfurt guards/live checks, isolated APK. Reviewed comparison screenshots from artifact `10596810629`; APK artifact `10597320142`. Stable/main refs reverified unchanged on 2026-09-20.

Read the complete listing editor and its existing contract tests. Implemented shared bounded action dock, scrolling correction/progress, constrained form surface, responsive field pairs and wrapping single-choice controls. Kept all validators, payload, persistence, identity checks, Sai and media methods byte-for-byte unchanged. Added seven widget cases for all five steps across narrow/enlarged/landscape RTL, rental draft payload and busy actions, title/tenure/location gates, unit identity and rental validation order. Editor analyze and six of seven new cases passed at `8aab16d`; companion CI `35483237033` found one test-finder ambiguity: Sai warning text exists both in section subtitle and SnackBar. Scoped the existing exact warning assertion to SnackBar; retained all validation/no-write assertions. Correction awaits full CI/APK.

# Next Exact Step

Publish the test-finder correction and require complete CI/APK. Diagnose any failure before expanding scope. Inspect editor visual artifacts, then cover remaining listing preview/evidence/Sai/map journeys and continue messaging. Do not repeat completed discovery/comparison work.

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
- `mobile_app/test/experimental_property_card_test.dart` — six RTL size/text cases plus rail and disabled-action regressions.
- `mobile_app/lib/features/properties/presentation/favorites_screen.dart` — shared card skeleton and selection surface; original comparison/remove logic.
- `mobile_app/lib/features/properties/presentation/property_details_screen.dart` — similar-property rail height compatibility only; full details redesign remains Phase 4.
- `mobile_app/lib/features/map/presentation/discovery_map_dock.dart` — responsive map context/mode/preview presentation only.
- `mobile_app/test/experimental_map_dock_test.dart` — simultaneous states, portrait/landscape RTL, input passthrough and every dock callback.
- `mobile_app/lib/features/map/presentation/discovery_search_sheet.dart` — existing search state/returns with responsive modal presentation.
- `mobile_app/test/experimental_discovery_search_test.dart` — eight keyboard/RTL/query/selection/clear/submit tests.
- `mobile_app/test/final_uat_polish_contract_test.dart` — moved visual-copy source assertion follows the extracted sheet; history and map wiring assertions retained/extended.
- `mobile_app/lib/features/map/presentation/discovery_filter_sheet.dart` — preserved filter state/validation with grouped responsive UI.
- `mobile_app/test/experimental_discovery_filter_test.dart` — 11 RTL/size/validation/reset/type/room regressions.
- `AppFieldPair` in the shared layouts — responsive input composition; no validation/controller ownership.
- `mobile_app/lib/features/map/presentation/discovery_results_layout.dart` — scrolling header and lazy results; original sort values.
- `mobile_app/test/experimental_discovery_results_test.dart` — six portrait/landscape RTL sort/lazy-scroll cases.
- `mobile_app/test/experimental_favorite_selection_test.dart` — comparison order placement, four-item cap and cancel.
- `mobile_app/test/experimental_property_details_test.dart` — responsive details, trust flags, role/status visibility, auth CTA and retry regressions.
- `AppActionDock` in shared layouts — bounded scrollable persistent action surface.
- Details summary/advertiser sections in the existing details screen; callbacks remain unchanged.
- `mobile_app/test/experimental_property_context_test.dart` — server wording, market/Sai loading/empty/error/retry and scaled RTL rendering.
- Gallery/frame/skeleton plus market/Sai presentation files — shared tokens and responsive layout only.
- Saved-search builder/list/results presentation files and `experimental_saved_search_test.dart` — responsive editor/list and ten behavior/layout cases.
- `property_compare_screen.dart` and `experimental_property_compare_test.dart` — aligned comparison table, original values/actions and six regression cases.
- `listing_editor_screen.dart` and `experimental_listing_editor_test.dart` — responsive five-step presentation and seven regression cases.
- This checkpoint.

# Screens Completed

Implemented and automated-verified: main navigation/discovery controls and results, property cards, favorites selection, comparison, saved-search editor/list/results, details summary/gallery/advertiser/Sai/market context. Full native/authenticated per-screen acceptance remains pending; no claim that all 71 presentation files are finished.

# Screens Remaining

Listing editor and related modals/pickers, messaging, account/KYC, management, support, financial/agreements, role-specific hubs, remaining secondary screens and router error presentation. See the inventory implementation ledger; native/authenticated acceptance still applies to previously automated-verified screens.

# Tests Last Run

- 2026-09-20, `8aab16d`: companion `35483237033` analyze/backend/PostGIS PASS; Flutter 299 passed, one failed due new warning finder matching subtitle and SnackBar. Exact SnackBar-scoped correction in this commit; no app logic change.


- 2026-09-20, `18677a9`: Experimental `35482673515` and companion `35482675141` SUCCESS including full Flutter analyze/tests, backend/PostGIS, live Frankfurt guards/load and isolated APK.
- 2026-09-20, editor working changes: `git diff --check`, `python3 scripts/verify_ui_locked_source.py` PASS (346 immutable files). Validator/persistence/identity/Sai/media method range compared byte-for-byte with parent. Flutter execution remains CI-only due local VM sandbox limitation.


- 2026-09-20: verified `35469555165` / cbf6519 complete SUCCESS: 286 Flutter tests plus compile-time guard, clean analyze/pub get, backend/PostGIS, Frankfurt checks and APK. Companion `35469558183` and saved-search `35469419123` SUCCESS.
- Comparison local preflight: 346-file guard and whitespace PASS; selection/load/retry/optional-market-failure code and area formatter compared exactly unchanged. Six new tests await CI.

- Visual review at fcf1bc7 artifact `10592695789`: normal top-of-details and full advertiser section inspected; 320px/2.4 market metrics inspected. Fullscreen capture occurred before synthetic image decoding; tests now await engine decoding in runAsync and assert a non-null RawImage before capture. No production image loading changed. Saved-search CI remains pending.

- 2026-09-19: `2a114f7`, experimental `35468704166`, complete SUCCESS including release APK.
- 2026-09-19: `fcf1bc7`, companion `35469151219` SUCCESS; experimental `35469149328` analyze/full Flutter/cloud guard/health/load/backend/PostGIS PASS; release APK running. Gallery/context test fixture and capture ordering corrections verified.
- Saved-search preflight: 346-file guard/whitespace PASS; full validation/submission/lifecycle and saved-card menu logic compared exactly unchanged. Ten new tests await CI.

- Gallery/context `1c449b8`, companion `35468915060`: analyze/backend/PostGIS and all six context cases PASS. Details capture traversal attempted to reach an already disposed earlier heading by scrolling forward; corrected capture order to match natural reading order. Two gallery tests encountered the default test HTTP 400 response; they now use an isolated deterministic PNG HTTP fixture restored in finally, with a separate failed-image fallback test. No production network behavior or action assertions changed. CI rerun required.

- 2026-09-19: test scheduling correction `2a114f78`: companion `35468706084` SUCCESS; experimental `35468704166` analyze/full Flutter including all new 12 details cases/backend/PostGIS PASS, APK still in progress. Artifact `10592625288`; inspected 320 normal summary/advertiser and enlarged advertiser. Scrolled captures intentionally clip off-viewport content; upcoming evidence adds top-of-page and advertiser-heading captures.
- Gallery/context local checks: 346-file immutable guard and whitespace PASS; details action methods, fullscreen page/controller/zoom and provider contracts compared unchanged. Eight additional tests not yet run.

- 2026-09-19: details `2a76610`, experimental `35468502283` and companion `35468504456`: analyze/backend/PostGIS PASS, all 12 new details cases PASS; one existing community-return test failed because its synthetic tap occurred at y=608 outside the 600px test viewport immediately after scroll. Added settling and centered ensureVisible plus hitTestable assertions before existing interactions. No route/count assertions removed; fix awaits CI.

- 2026-09-16: `34990219383` at `cd9ab965`: pub get/analyze, 255 Flutter cases, compile-time UAT guard, Laravel/PostGIS, Frankfurt health/load, APK/package verification ALL PASS. Companion `34990224480` SUCCESS.
- 2026-09-16: main/stable refs rechecked and still exactly the Initial main SHA / Latest stable source SHA above. No production action.
- Details preflight: immutable 346-file verifier, whitespace, exact State/actions/provider/gallery/fact/trust-predicate comparison PASS. Twelve new rendered details cases await CI.

- Search `34988479360`, SHA `b5dea675`: full experimental CI/APK SUCCESS. Filters and result controls await their final-head run.

- Map polish `34987573433`, SHA `29f087c`: full experimental workflow SUCCESS, including APK. Companion `34987576488` also SUCCESS.
- Search `34988484659`, SHA `b5dea675`: companion workflow SUCCESS; main experimental `34988479360` in progress at checkpoint.
- Advanced-filter preflight: 346-file source guard and whitespace check PASS; exact filter State/validation comparison and map handler comparison PASS. New tests await CI.

- Map dock run `34958864562`, SHA `7fa15d7`: complete SUCCESS, 229 Flutter tests, analyze/backend/PostGIS/Frankfurt/APK. Visual artifact `10392751138`, APK artifact `10392458132`. Four dock images inspected; 320px/2.4 word-wrap issue addressed separately at `29f087c`.
- Search preflight: exact map source comparison (only search-widget binding changed), `git diff --check` and immutable 346-file verifier PASS. Search tests pending fresh CI.

- 2026-09-15: companion run `34957760977`, SHA `cd483d5`, SUCCESS; analyze and all 226 Flutter tests including UAT compile-time guard, Laravel and PostgreSQL/PostGIS. Experimental APK run `34957755283` still building at this checkpoint.
- 2026-09-15: live protected refs rechecked: main `5b2c226aca467fc8ec392782d6e2a1a0d7271bb6`, stable `46b8fed8fd119b223d4a1e67312d38ff9429e569`, both unchanged. No production access/deployment.
- Dock preflight: `git diff --check`, locked-source verifier, exact map State/native options/drawing-overlay comparison PASS. New tests await CI.

- 2026-09-15: run `34911352983`, SHA `f02a114`: all experimental CI jobs SUCCESS, including Flutter pub get/analyze/full tests, backend/PostGIS, Frankfurt endpoint/health/load, APK build and isolated package verification. Replaces failed runs `34910573934` and `34911058132`; sliver interaction and loading scheduling regressions resolved.
- Marketplace local preflight: `git diff --check`, 346-file immutable source verifier, and exact comparison of map State/query/navigation source PASS. Flutter regression awaits new CI; local VM limitation remains.

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
- UI Bug audit: similar-card fixed height and map-result fixed height addressed with shared cards/rail; preview and bottom-overlay replacement implemented pending CI. Full details and remaining discovery controls still need per-screen QA.
- Delivery environment: direct `git push` has no local credential. GitHub connector create-tree/create-commit/non-forced update-ref succeeded. Local tree was verified identical, then aligned with the published SHA via fetch + soft reset. Do not request or expose a token.
- Visual QA harness issue RESOLVED: corrected artifact `10364505958` inspected at all four widths / both scales. Supersedes square-glyph artifact `10363582427`. These remain isolated component images, not authenticated Android screen evidence.
- Earlier Phase 0/1 APKs use the baseline UAT application ID. The Phase 2 packaging commit changes only experimental application ID and launcher label; compiled package verification passed in run `34884689076`. Namespace/native channels/deep-link scheme/permissions/debug signing stay unchanged, and file-provider authority follows packageName dynamically.
- Discovery cards/dock/search/filter/sort and favorites comparison passed CI at cd9ab965. Saved-search secondary screens and complete journey visual review remain open.
- Regression discovered by source review: LayoutBuilder in feedback is incompatible with SliverFillRemaining(hasScrollBody:false) intrinsic sizing used by Messages and My Listings. Replaced it with intrinsic-safe centered scrolling; added a rendered sliver/retry test and retained a meaningful no-competing-inner-scroll assertion. Verified in run `34911352983`.
- CI Environment: run `34910136499` failed in Android setup before Flutter because the default legacy `tools` package is unavailable. Experimental workflow now explicitly requests supported `platform-tools`; SDK command-line setup and every analyzer/test/APK gate remain enabled.
- UI Bug: visual inspection found white tonal-button text on a pale container, inherited from the global FilledButtonTheme. An explicit tonal foreground and rendered contrast regression are implemented in a separate change; verified in run `34911352983`.
- Visual test scheduling RESOLVED: jump-to-scroll interactions settle before tapping; continuously animated loading uses a single frame. No action assertions were removed.
- No WHY_BACKEND_CHANGE_IS_NEEDED: none identified; backend changes are not planned.

# Decisions

- Related rail uses a content-height horizontal Row only for the existing server-bounded similar-property set (`PropertyController::show`, limit 6). Large marketplace results remain lazy lists. No field, sort or request was added.

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
