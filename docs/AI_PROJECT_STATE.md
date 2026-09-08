# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current gate — Phase 3 CLOSED / Phase 4 next

Phase 3 — Buyer Discovery Completion + Server-side Favorites is CLOSED by explicit product-owner acceptance after successful automated gates and real-device Android acceptance.

Branch: `phase3/buyer-discovery-favorites`
PR: #15 targeting `phase1/ux-product-foundation`
Canonical tracker: Issue #13

Accepted Phase 3 outcome:
- Laravel-authoritative, account-bound server Favorites;
- Supabase UAT `property_favorites` table with deny-all direct Data API posture (RLS enabled, zero policies, direct table/sequence privileges revoked from `PUBLIC`, `anon`, and `authenticated`);
- anonymous published-only discovery with internal listing-review metadata removed from public property payloads;
- real Account -> Favorites screen and favorite hearts in details, similar cards, list results, and selected-map preview;
- anonymous -> WhatsApp/profile -> return-to-property -> pending favorite handoff;
- deterministic newest/price/distance list sort modes;
- owned Android property app deep links (`realestate://app/properties/{id}`);
- existing property-linked messaging retained as the only advertiser contact path;
- dedicated Phase 3 Laravel + PostgreSQL 17/PostGIS + Flutter + release APK CI.

Final automated acceptance evidence:
- accepted CI head: `44af494bd3dd586b693903ced5901e9d143f2d90`;
- Phase 3 Buyer Discovery CI run #34 / `34174945119`: SUCCESS;
- Phase 2 regression on the same head: SUCCESS;
- APK artifact: `real-estate-phase3-uat-apk-34`;
- artifact digest: `sha256:3ed8a4f6a8343c6346ff54b6e15a191da9ee32f41901a781ec1edade78cd1631`.

The product owner subsequently installed/tested the candidate and explicitly marked Phase 3 accepted on a real Android device.

Important deployment boundary: this acceptance does not independently establish the current Render service branch/deploy state. The last confirmed Render configuration before closure tracked the older `audit/system-stabilization` branch with auto-deploy disabled. Re-check Render before claiming Phase 3 backend code is live there. No Production deploy is implied.

PR #15 is not merged yet. Merge remains a separate explicit product-owner approval gate.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Integration branch: `phase1/ux-product-foundation`
- Current accepted feature branch: `phase3/buyer-discovery-favorites`
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

Phase 1 — UX/UI Product Foundation is CLOSED.

Accepted outcome includes Arabic RTL-first Material 3 design, marketplace-first role navigation, anonymous public discovery, services under Account, standardized property UI primitives, deferred request/matching removal, and Laravel/Flutter closure CI.

The startup viewport defect later discovered on-device was repaired in PR #10, passed automated regression, was installed by the product owner, and was explicitly accepted before Phase 3 proceeded.

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

PR #9 was merged with product-owner approval into `phase1/ux-product-foundation`, not into `main`.

## Phase 3 status

Phase 3 — Buyer Discovery Completion + Server-side Favorites is CLOSED.

Accepted outcome:
1. public search/filter/sort/list/map hardening;
2. property-card/details consistency and unavailable/error states;
3. public privacy boundary;
4. server/account-bound Favorites with Laravel API + Supabase deny-all direct access;
5. anonymous authentication handoff for favorite actions;
6. valid owned app deep links/share reference;
7. correct property-linked contact entry;
8. Laravel/PostgreSQL/PostGIS/Flutter/APK regression gates;
9. explicit product-owner Android device acceptance.

See `docs/PHASE3_BUYER_DISCOVERY.md` for detailed evidence.

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

## Next phase — Phase 4

Phase 4 is property-linked conversation, messaging, viewing, and booking integration hardening.

It should harden the existing implementation rather than build a second chat/viewing system. Focus areas include:
- property-linked conversation lifecycle and deep links;
- message reliability, unread/read state, privacy and reporting boundaries;
- viewing request -> accept/reschedule/reject/cancel/complete state machine UX;
- conversation/viewing linkage and history;
- concurrency/conflict handling and notifications;
- Laravel/PostgreSQL/Flutter/APK regression and real-device acceptance.

Phase 4 must not expand into Production deployment, payments, Property Requests/Researcher Matching, rental contracts, valuation, or legal-library work.

## Deferred / not launch-critical

Property Requests, Researcher Requests, and broker-driven request matching remain deferred unless explicitly re-approved by the product owner.

They must not be exposed as active capabilities, launch-facing quick actions, or mandatory roadmap steps.

## Later launch-critical work after Phase 4

- rental contracts and in-app agreement workflow;
- price indicators + valuation using eligible published platform data only;
- Real-estate Guide + Legal Documents library;
- Production/security/operations readiness;
- closed beta -> soft launch -> public launch.

## Execution model

This ChatGPT session owns engineering work executable through available repository/cloud tools: roadmap decomposition, GitHub changes, CI review, Laravel/API/database/security work, Render/Supabase verification, Flutter source changes, tests, and documentation.

Real-device subjective visual acceptance remains a manual/Beta gate when an actual device is required. Lack of Computer Use must not freeze normal development.

## Update rule

Whenever accepted behavior, roadmap, architecture, or product direction changes, update this file and the relevant workflow/decision/changelog docs. Current Git/code and explicit newer product-owner decisions outrank stale historical documentation.
