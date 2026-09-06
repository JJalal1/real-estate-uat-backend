# AI Project State — REAL ESTATE UAT

Last prepared: 2026-09-05

## Current repository baseline

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Baseline commit at AI-system setup: `f76b5c15e3f6918a93c4781d051c2703f7a23409`
- Baseline commit message: `Update services screen CI baseline`
- Previous feature commit: `674b6ef006b3a84a43539f9b3c11b37286e1756f` (`Add free services hub and reorganize account`)
- GitHub Actions workflow: `.github/workflows/build-uat-apk.yml`
- Baseline workflow run: Build UAT Android APK run #16, successful.

This document records the known state at setup time. Always re-check Git HEAD and live CI before relying on the SHA above.

## Current architecture

- Mobile: Flutter Android.
- Backend: Laravel/PHP API.
- Database: PostgreSQL with PostGIS.
- Storage: Supabase Storage, treated as private for sensitive data.
- UAT backend hosting: Render.
- Source control / CI: GitHub + GitHub Actions.

Current repository roots include:

- `backend-api-runtime/`
- `mobile_app/`
- `.github/workflows/`
- `render.yaml`
- `docs/`

## Current UAT endpoints and build constants

Known current mobile UAT API base:

`https://real-estate-uat-api.onrender.com/api`

Known public health endpoint:

`https://real-estate-uat-api.onrender.com/api/health`

Known public properties endpoint:

`https://real-estate-uat-api.onrender.com/api/properties`

GitHub Actions currently uses:

- Flutter `3.27.3`
- Java `17`
- `APP_ENVIRONMENT=uat`
- Android application id `com.example.real_estate_mobile`

## Cloud UAT

Known project handoff state:

- Render service: `real-estate-uat-api`
- Render runtime: Docker
- Render plan: free
- Supabase PostgreSQL/PostGIS is the UAT database
- Supabase Storage bucket: `real-estate-uat`
- UAT storage is private by product/security rule

The handoff previously identified a likely latency issue caused by geographic distance between Render and Supabase. Verify the live Render region and Supabase region before taking performance action; do not assume old region notes are still current.

## Implemented/high-confidence areas

- Flutter app and Laravel API are in the same GitHub repository.
- GitHub Actions builds a UAT Android APK from `main` when mobile/workflow paths change.
- Workflow includes accepted-file hash guards, Flutter analyze/tests, a live UAT health check, and APK artifact upload.
- UAT phone/OTP test mode exists and is staging-only by design.
- Account verification supports professional profile types `owner`, `broker`, `office`.
- Support roles and shared support-task claim behavior exist in backend code.
- Three-role operational workspaces for support agent, support manager, and platform owner were added before the current baseline.
- Free-services phase 1 is implemented: backend `/api/services/hub`, free pricing model, paid features disabled in the active journey, unified services UI, and account-page reorganization.
- The accepted mobile baseline now includes the free-services screen.

## Product constraints already accepted

- No Production work yet.
- No real payment flow.
- No paid listing/account promotion or paid service packages in the active product.
- No broker hierarchy or exclusive broker-region ownership.
- Backend authorization is authoritative.
- Published listings are public.
- Shared queue → claim remains the normal support-work model.

## Open product roadmap

### Phase 2 — next major product phase

Property Requests + Researcher Requests + Suggestions/Matching.

Target journey:

`property request -> eligible verified broker/office sees request -> suggests one of own approved published properties -> requester receives notification -> opens property -> conversation -> viewing request`

Expected backend work includes real persistent entities, authorization, statuses, matching filters, duplicate-suggestion protection, notifications, and links to existing property/conversation/viewing flows.

Implementation is in progress on `feature/property-requests-phase2`: persistent requests and suggestions, verified broker/office matching, requester notifications, and Flutter request/researcher journeys are included for review and UAT validation.

Phase 2 researcher matching uses structured `geo_cell_id`, exact currency, operation/type, budget, area, and room filters. The current UAT query considers at most the researcher's latest 250 eligible published properties and returns at most 300 current matching requests; revisit this bound with pagination or a normalized matching index before Production-scale use.

### Later phases

- server-side Favorites
- viewing/booking/conversation integration hardening
- Rental Contracts
- Price Indicators + Property Valuation using one backend data engine
- Real-estate Guide + Legal Documents library
- deeper performance profiling if cloud-region alignment does not solve latency

## Current AI-development setup status

- GitHub connection: available to ChatGPT.
- Repository access: confirmed.
- AI operating docs: being installed through branch `ai/project-operating-system`.
- Render ChatGPT plugin: pending connection at setup time.
- Supabase ChatGPT plugin: pending connection at setup time.
- Future coding flow should prefer branch + PR + CI over ZIP/manual patching when repository write tools are available.

## Update rule

Whenever a feature PR changes an accepted workflow, update this file in the same PR or immediately after acceptance. Do not let this document become a replacement for inspecting the current code.
