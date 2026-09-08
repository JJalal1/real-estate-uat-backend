# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current gate — Phase 3 Buyer Discovery Completion

Phase 3 is actively implemented on `phase3/buyer-discovery-favorites` with Draft PR #15 targeting `phase1/ux-product-foundation`. Canonical tracker: Issue #13.

The startup-navigation blocker from Issue #11 / PR #10 is CLOSED: the product owner installed the corrected Android candidate and explicitly confirmed that it works on the reporting device. PR #10 was merged with approval into the integration branch at `524f9a9acf3a83d8dbbcba5712e0d8c06b4d3174`.

Phase 3 implementation currently includes:
- Laravel-authoritative, account-bound server Favorites;
- Supabase UAT `property_favorites` table with deny-all direct Data API posture (RLS enabled, zero policies, direct table/sequence privileges revoked from `PUBLIC`, `anon`, and `authenticated`);
- anonymous published-only discovery with internal listing-review metadata removed from public property payloads;
- real Account -> Favorites screen and favorite hearts in details, similar cards, list results, and selected-map preview;
- anonymous -> WhatsApp/profile -> return-to-property -> pending favorite handoff;
- deterministic newest/price/distance list sort modes;
- owned Android property app deep links (`realestate://app/properties/{id}`);
- existing property-linked messaging retained as the only advertiser contact path;
- dedicated Phase 3 Laravel + PostgreSQL 17/PostGIS + Flutter + release APK CI.

The application-code acceptance head before docs-only state commits is `b671c90d0d122e0afd023948445054931b2343a9`. Re-check current GitHub Actions before reporting final acceptance; documentation-only commits after this SHA do not change application/runtime behavior.

Do not mark Phase 3 CLOSED until the latest application-code gate has completed successfully. A true real-device Favorites end-to-end acceptance also requires a Render UAT deployment containing the Phase 3 Laravel routes. The current Render UAT service still tracks the older `audit/system-stabilization` branch with auto-deploy disabled, so do not claim the new Favorites API is live on Render yet.

See `docs/PHASE3_BUYER_DISCOVERY.md` for detailed scope and acceptance rules.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Integration branch: `phase1/ux-product-foundation`
- Current feature branch: `phase3/buyer-discovery-favorites`
- Mobile: Flutter Android
- Backend: Laravel/PHP API
- Database: PostgreSQL 17 + PostGIS
- Storage: private Supabase Storage
- UAT runtime: Render
- Source control / CI: GitHub + GitHub Actions

Always re-check Git HEAD, CI, Render UAT, and Supabase UAT before relying on historical SHAs.

## Phase 0 status

Phase 0 — Full System Audit & Stabilization is CLOSED by explicit product-owner decision.

Accepted audit work includes authorization/navigation/notification fixes, Supabase hardening, UAT runtime fixes, deterministic CI, load regression coverage, and UAT deployment verification.

## Phase 1 status

Phase 1 — UX/UI Product Foundation is CLOSED at source/automated-acceptance level.

Accepted outcome includes Arabic RTL-first Material 3 design, marketplace-first role navigation, anonymous public discovery, services under Account, standardized property UI primitives, deferred request/matching removal, and Laravel/Flutter closure CI.

Rendered-device visual inspection remains a Beta/launch-readiness gate. Blocking device defects take priority when discovered; the startup viewport defect discovered after Phase 2 was repaired and device-confirmed before Phase 3 proceeded.

## Phase 2 status

Phase 2 — Listing Journey Hardening is CLOSED.

Accepted outcome:
- explicit `Save Draft -> Preview -> Submit for Review` UX;
- canonical create/edit/location/media/property-proof editor;
- returned-for-correction state/reason survives editing until explicit resubmission;
- normalized My Listings lifecycle/actions;
- shared support queue/claim and transaction/row-lock review protection;
- exact duplicate publication blocking plus explainable likely-duplicate human-review signals;
- correction/approval/rejection notifications;
- public visibility restricted to published listings;
- Laravel, PostgreSQL 17/PostGIS, Flutter and APK acceptance gates.

PR #9 was merged with product-owner approval into `phase1/ux-product-foundation` at `d5ea7938e5fe63868a1a36b979221581927e9e3e`, not into `main`.

## Current product direction

REAL ESTATE is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> favorite/share/contact -> property conversation -> viewing -> agreement`

Key rules:
- Published properties are publicly browsable without login.
- Favorites are account-bound server data; local-only favorites are not the final product.
- Owner, broker, and real-estate office are the supported professional identities.
- Listing publication uses shared support queue -> claim.
- Exact physical-property duplicate publication is blocked; fuzzy suspicion is human review, not automatic rejection.
- No broker hierarchy, regional broker exclusivity, or territory ownership.
- Viewing/contact starts from a specific property and reuses the single messaging system.
- The active product remains free; no paid promotion/upgrades/packages are active.
- Backend authorization is authoritative.
- Sensitive storage remains private.

## Phase 3 scope

Phase 3 completes buyer discovery rather than rebuilding it:
1. public search/filter/sort/list/map hardening;
2. property-card/details consistency and unavailable/error states;
3. public privacy boundary;
4. server/account-bound Favorites with Laravel API + Supabase deny-all direct access;
5. anonymous authentication handoff for favorite actions;
6. valid app deep links/share reference;
7. correct property-linked contact entry;
8. Laravel/PostgreSQL/PostGIS/Flutter/APK regression gates.

Phase 3 must not expand into rental contracts, valuation, Production infrastructure, payment activation, or deferred request/matching features.

## Deferred / not launch-critical

Property Requests, Researcher Requests, and broker-driven request matching remain deferred unless explicitly re-approved by the product owner.

They must not be exposed as active capabilities, launch-facing quick actions, or mandatory roadmap steps.

## Later launch-critical work after Phase 3

- Phase 4: property-linked conversation/viewing/booking integration hardening;
- rental contracts and in-app agreement workflow;
- price indicators + valuation using eligible published platform data only;
- Real-estate Guide + Legal Documents library;
- Production/security/operations readiness;
- closed beta -> soft launch -> public launch.

## Execution model

This ChatGPT session owns engineering work executable through the available repository/cloud tools: roadmap decomposition, GitHub changes, CI review, Laravel/API/database/security work, Render/Supabase verification, Flutter source changes, tests, and documentation.

Real-device subjective visual acceptance remains a manual/Beta gate when an actual device is required. Lack of Computer Use must not freeze normal development.

## Update rule

Whenever accepted behavior, roadmap, architecture, or product direction changes, update this file and the relevant workflow/decision/changelog docs. Current Git/code and explicit newer product-owner decisions outrank stale historical documentation.
