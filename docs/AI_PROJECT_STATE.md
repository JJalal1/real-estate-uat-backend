# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-07

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Current product branch: `phase1/ux-product-foundation`
- Phase 1 branch starts from the accepted Phase 0 audit head `fb1263b58ea4b23af2a597d97de69c49e301f3a9`.
- Mobile: Flutter Android.
- Backend: Laravel/PHP API.
- Database: PostgreSQL + PostGIS.
- Storage: private Supabase Storage.
- UAT runtime: Render.
- Source control / CI: GitHub + GitHub Actions.

Always re-check Git HEAD, CI, Render UAT, and Supabase UAT before relying on historical SHAs.

## Phase 0 status

Phase 0 — Full System Audit & Stabilization is considered CLOSED by explicit product-owner decision on 2026-09-07.

The accepted audit work includes authorization/navigation/notification fixes, Supabase hardening, UAT runtime fixes, deterministic CI, load regression coverage, and UAT deployment verification. Visual inspection is not being used to reopen Phase 0; rendered-device inspection continues as the first evidence task of Phase 1 so the UX redesign starts from the real product baseline.

## Current product direction

REAL ESTATE is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> contact advertiser -> property conversation -> viewing -> agreement`

Key rules:

- Published/approved properties are publicly browsable without login.
- Owner, broker, and real-estate office are the supported professional identities.
- Listing publication is reviewed through shared support queue -> claim.
- The backend prevents duplicate publication when listings resolve to the same physical `PropertyAsset`; this remains a core rule and may later be strengthened with similarity detection.
- No master/sub-broker hierarchy, regional broker exclusivity, or broker territory ownership.
- Viewing starts from a specific property.
- The active product remains free from the user's perspective; no paid promotion/upgrades/packages are active.
- Backend authorization is authoritative.
- Sensitive storage remains private.

## Current phase — Phase 1 UX/UI Product Foundation

Issue: #6
Branch: `phase1/ux-product-foundation`
Detailed execution plan: `docs/PHASE1_UX_PRODUCT_FOUNDATION.md`

Phase 1 priorities:

1. capture current rendered baseline with Work/Astra + Computer Use;
2. simplify information architecture and role-aware navigation;
3. establish one RTL-first design system;
4. redesign current surfaces incrementally in small reviewable tasks;
5. preserve current backend/business/security behavior while improving the experience.

## Deferred / not launch-critical now

Property Requests, Researcher Requests, and broker-driven request matching are not the platform's core journey and are deferred unless the product owner explicitly re-approves them later.

They must not be treated as the next mandatory phase or as a prerequisite for launch.

## Later launch-critical work after Phase 1

- complete property listing/publishing UX and stronger duplicate-detection workflow;
- public discovery/search/filter/map/property-detail experience;
- server-side favorites;
- property-linked conversation/viewing/booking integration hardening;
- rental contracts and in-app agreement workflow;
- price indicators + property valuation using eligible published data only;
- Real-estate Guide + Legal Documents library;
- Production/security/operations readiness;
- closed beta -> soft launch -> public launch.

## AI execution split

Ordinary ChatGPT session owns:
- roadmap/task decomposition;
- GitHub/CI review;
- Laravel/API/database/security;
- Render/Supabase UAT verification;
- documentation and task acceptance.

Work/Astra owns primarily:
- rendered-device inspection via Computer Use;
- UX/UI proposals;
- Flutter visual implementation;
- visual regression evidence.

Work tasks must remain small and stop after the requested scope.

## Update rule

Whenever accepted behavior, roadmap, architecture, or product direction changes, update this file and the relevant business/workflow/decision docs. Current Git/code and explicit newer product-owner decisions outrank stale historical roadmap text.
