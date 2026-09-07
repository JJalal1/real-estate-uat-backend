# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current gate — startup navigation blocker (Issue #11 / PR #10)

The product owner's device video exposed a blocking layout defect: the anonymous property/account navigation occupied the entire screen and left no usable page body. This takes priority over starting Phase 3; previous source/automated phase acceptance is not evidence of device usability.

- Active repair branch: `fix/startup-navigation-layout`, based on integration commit `d5ea7938e5fe63868a1a36b979221581927e9e3e`.
- Regression-only commit `e82234399e73b35e10a7991790142092f1dd6e60`, CI run #47 (`34170985433`): existing 102 Flutter tests passed, all 36 new viewport tests failed. Navigation height equalled the full 568/915 pixel test viewport.
- Fix commit `e3eb8df60ec70fac924c74c677109f9e357daaa9`: remove cross-axis stretching and shrink destination Columns to their content in `AppNavigationBar`. No route, auth, backend or cloud changes.
- Run #48 (`34171053202`) passed Laravel, PostgreSQL/PostGIS, Flutter analysis, full Flutter tests including the 36 new viewport/body-interaction cases, and compile-time UAT configuration. APK build/upload was still running when this checkpoint was written; read the current run/artifact status and PR #10 before reporting final build success.
- The new tests cover six role destination sets, two phone sizes and three text scales with the bundled Arabic font. They are widget-layout/hit-testing evidence, not full real-device/map acceptance.
- Issue #11 remains OPEN pending verification of the corrected APK on the reporting device. Do not claim this device defect closed based on CI alone.
- PR #10 remains subject to a separate product-owner merge approval. Approval already given for PR #9 is not blanket approval for future PRs.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Current integration branch: `phase1/ux-product-foundation`, containing Phase 2 through merge commit `d5ea7938e5fe63868a1a36b979221581927e9e3e`.
- Phase 2 was based on Phase 1 closure candidate `a624d5bb6e006b6835e25b2ed1dd6893e08d9a70`.
- Mobile: Flutter Android.
- Backend: Laravel/PHP API.
- Database: PostgreSQL + PostGIS.
- Storage: private Supabase Storage.
- UAT runtime: Render.
- Source control / CI: GitHub + GitHub Actions.

Always re-check Git HEAD, CI, Render UAT, and Supabase UAT before relying on historical SHAs.

## Phase 0 status

Phase 0 — Full System Audit & Stabilization is CLOSED by explicit product-owner decision.

The accepted audit work includes authorization/navigation/notification fixes, Supabase hardening, UAT runtime fixes, deterministic CI, load regression coverage, and UAT deployment verification.

## Phase 1 status

Phase 1 — UX/UI Product Foundation is CLOSED at source/automated-acceptance level.

Accepted outcome:
- Arabic RTL-first Material 3 design system and reusable components;
- marketplace-first role-aware navigation;
- public property discovery preserved without login;
- services moved under Account;
- standardized property-details conversion surface and reusable property UI primitives;
- deferred Property Requests / Researcher Requests / matching removed from the launch-facing services contract and UI;
- Phase 1 closure CI validates Laravel plus Flutter analysis/tests/release APK build.

Rendered-device visual inspection remains a required Beta/launch-readiness gate rather than a blocker for normal engineering progress. Known blocking device defects must nevertheless be repaired before new feature expansion, as tracked above.

## Phase 2 status

Phase 2 — Listing Journey Hardening is CLOSED at source/automated-acceptance level.

Accepted outcome:
- explicit `Save Draft -> Preview -> Submit for Review` UX with no implicit submission;
- canonical listing editor for create/edit/location/media and structured owner property-relationship evidence;
- returned-for-correction state/reason survives editing until explicit resubmission;
- My Listings lifecycle/actions normalized around actual server states;
- shared support queue/claim and sensitive review decisions hardened with stronger transaction/row-lock protection;
- exact `PropertyAsset` duplicate blocking preserved;
- explainable likely-duplicate detection added from geography/address/property-fact signals;
- uncertain duplicate suspicion requires human review, not fuzzy automatic rejection;
- correction/approval/rejection notifications link to the actual property;
- public visibility remains restricted to approved/published listings;
- dedicated Phase 2 CI covers full Laravel regression, PostgreSQL 17 + PostGIS migration/security/lifecycle acceptance, Flutter analysis/tests, UAT endpoint verification, and release APK build/upload.

Final automated acceptance evidence:
- Phase 2 gate head: `a8226f9ac5c8375828c34451150f2736960d0725`;
- GitHub Actions run #42 / `34169314754`: SUCCESS;
- UAT APK artifact: `real-estate-phase2-uat-apk-42`.

PR #9 was merged with product-owner approval into `phase1/ux-product-foundation`, not `main`, at `d5ea7938e5fe63868a1a36b979221581927e9e3e`.

The Render UAT service still tracks the older stabilization branch with auto-deploy disabled; do not describe Phase 2 as live Render UAT until the approved integration/deployment sequence is performed.

## Current product direction

REAL ESTATE is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> contact advertiser -> property conversation -> viewing -> agreement`

Key rules:
- Published/approved properties are publicly browsable without login.
- Owner, broker, and real-estate office are the supported professional identities.
- Listing publication is reviewed through shared support queue -> claim.
- Exact physical-property duplicate publication is blocked by `PropertyAsset`; likely matches are explainable human-review signals.
- No master/sub-broker hierarchy, regional broker exclusivity, or broker territory ownership.
- Viewing starts from a specific property.
- The active product remains free from the user's perspective; no paid promotion/upgrades/packages are active.
- Backend authorization is authoritative.
- Sensitive storage remains private.

## Next phase after startup repair — Phase 3 Buyer Discovery Completion

Phase 3 starts from the existing public discovery implementation rather than rebuilding it.

Phase 3 scope:
1. normalize property cards across list/map/details surfaces;
2. harden public search, filters, sorting, bounds/pagination and published-only boundaries;
3. verify map/list consistency and similar-property correctness;
4. improve media/loading/error/cache behavior where measured evidence justifies it;
5. implement server/account-bound Favorites with database/API/auth/Flutter/tests;
6. polish share/contact entry points without creating parallel messaging/viewing systems.

Phase 3 must not expand into Rental Contracts, valuation, Production infrastructure, payment activation, or deferred request/matching features.

## Deferred / not launch-critical

Property Requests, Researcher Requests, and broker-driven request matching are deferred unless the product owner explicitly re-approves them later.

They must not be exposed as active capabilities, launch-facing quick actions, or mandatory roadmap steps.

## Later launch-critical work after Phase 3

- property-linked conversation/viewing/booking integration hardening;
- rental contracts and in-app agreement workflow;
- price indicators + property valuation using eligible published data only;
- Real-estate Guide + Legal Documents library;
- Production/security/operations readiness;
- closed beta -> soft launch -> public launch.

## Execution model

This ChatGPT session owns the engineering work that available repository/cloud tools can execute: roadmap decomposition, GitHub changes, CI review, Laravel/API/database/security work, Render/Supabase verification, Flutter source changes, tests, and documentation.

Real-device subjective visual acceptance remains a manual/Beta gate when an actual Android device or emulator is available; lack of Computer Use must not freeze ordinary feature development.

## Update rule

Whenever accepted behavior, roadmap, architecture, or product direction changes, update this file and the relevant business/workflow/decision docs. Current Git/code and explicit newer product-owner decisions outrank stale historical roadmap text.
