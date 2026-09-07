# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Current accepted product branch: `phase1/ux-product-foundation`
- Phase 1 branch starts from the accepted Phase 0 audit head `fb1263b58ea4b23af2a597d97de69c49e301f3a9`.
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

Rendered-device visual inspection is still valuable, but it is no longer a blocker that keeps Phase 1 open. It is a required Beta/launch-readiness gate before public release.

## Current product direction

REAL ESTATE is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> contact advertiser -> property conversation -> viewing -> agreement`

Key rules:
- Published/approved properties are publicly browsable without login.
- Owner, broker, and real-estate office are the supported professional identities.
- Listing publication is reviewed through shared support queue -> claim.
- The backend prevents duplicate publication when listings resolve to the same physical `PropertyAsset`; later similarity detection may strengthen this without silently merging unrelated properties.
- No master/sub-broker hierarchy, regional broker exclusivity, or broker territory ownership.
- Viewing starts from a specific property.
- The active product remains free from the user's perspective; no paid promotion/upgrades/packages are active.
- Backend authorization is authoritative.
- Sensitive storage remains private.

## Next phase — Phase 2 Listing Journey Hardening

Phase 2 starts immediately after Phase 1 closure and does not rebuild the listing system from scratch.

Phase 2 scope:
1. normalize Add Property and My Listings onto the accepted design system;
2. separate Save Draft / Preview / Submit for Review clearly in the UX while preserving backend workflow authority;
3. harden create/edit/media/location/evidence/review/resubmission states;
4. verify the full listing lifecycle end-to-end through automated tests and UAT-safe checks;
5. strengthen likely-duplicate detection and support review without automatic destructive merges;
6. preserve the current verified owner/broker/office verification rules and shared support claim model.

Phase 2 must not expand into Favorites, Rental Contracts, valuation, Production infrastructure, payment activation, or deferred request/matching features.

## Deferred / not launch-critical

Property Requests, Researcher Requests, and broker-driven request matching are deferred unless the product owner explicitly re-approves them later.

They must not be exposed as active capabilities, launch-facing quick actions, or mandatory roadmap steps.

## Later launch-critical work after Phase 2

- buyer discovery/search/filter/map/property-detail hardening;
- server-side favorites;
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
