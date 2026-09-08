# AI Change Log — REAL ESTATE

Use this as a concise history of AI-assisted engineering milestones. It is not a substitute for Git history.

## 2026-09-08 — Phase 3 buyer discovery + server-side Favorites accepted

Branch: `phase3/buyer-discovery-favorites`
PR: `#15`
Tracker: `#13`

High-level accepted result:
- completed anonymous published-only discovery hardening across list/map/details;
- removed internal listing-review metadata from public property payloads;
- added Laravel-authoritative, account-bound server Favorites with idempotent add/remove/list/status behavior and account isolation;
- added Supabase UAT `property_favorites` with RLS enabled, zero permissive policies, and direct `PUBLIC`/`anon`/`authenticated` access revoked;
- replaced fake Favorites UI with a real account-backed screen and heart state across property details, similar cards, list results, and selected-map preview;
- preserved anonymous favorite intent through authentication/profile completion and return-to-property;
- corrected deterministic newest sorting while retaining price/distance modes;
- added owned Android property deep links using `realestate://app/properties/{id}`;
- retained the single property-linked conversation endpoint as the advertiser-contact path;
- added dedicated Phase 3 Laravel, PostgreSQL 17/PostGIS, Flutter, UAT compile configuration, and release APK gates.

Final automated evidence:
- Phase 3 Buyer Discovery CI run #34 / `34174945119`: SUCCESS on head `44af494bd3dd586b693903ced5901e9d143f2d90`;
- Phase 2 regression on the same accepted head: SUCCESS;
- APK artifact `real-estate-phase3-uat-apk-34`;
- artifact digest `sha256:3ed8a4f6a8343c6346ff54b6e15a191da9ee32f41901a781ec1edade78cd1631`.

The product owner subsequently installed/tested the Phase 3 Android candidate and explicitly accepted the phase on a real device. This acceptance does not by itself prove the current Render branch/deploy state; Render must be re-verified before claiming the Phase 3 backend is live there. No Production deployment or merge to `main` is implied.

Next engineering phase: Phase 4 — property-linked conversation, messaging, viewing, and booking integration hardening.

## 2026-09-07 — Phase 0 system audit and stabilization

Branch: `audit/system-stabilization`
Draft PR: `#5`

Phase 2 feature development is frozen while the accepted system is stabilized.

High-level result of the automated/server-side audit:

- inventoried the reachable Flutter routes, role shells, dialogs, and major backend surfaces;
- removed the hard-coded duplicate chat surface and retained the API-backed messaging flow;
- made malformed message/property deep links fail safely instead of crashing;
- repaired notification destinations for current KYC, support, task, booking, property, service, and messaging entities;
- enforced shared-task ownership on all unified KYC review decisions;
- repaired report-close notification destinations;
- preserved local logout cleanup even when the server is unreachable;
- reconciled accepted UAT migrations with the live Supabase database;
- hardened the Supabase `public` schema by enabling RLS, revoking direct `anon`/`authenticated` table access, pinning trigger-function search paths, and protecting future public tables;
- added/verified PostgreSQL foreign-key and PostGIS regression coverage;
- expanded GitHub Actions to test Laravel, PostgreSQL/PostGIS, Flutter analysis/tests, the compiled UAT endpoint, live Render health, a read-only concurrent UAT load probe, and the release APK;
- corrected Render runtime/port startup behavior and added the UAT cloud-readiness guard;
- tuned Apache prefork capacity to 12 workers, below the Supabase session-pool ceiling with operational headroom;
- tested and rejected persistent PostgreSQL sessions as unnecessary for the accepted UAT baseline; the final baseline remains non-persistent;
- verified the live Render service after deployment and verified Supabase connection state normalized without application-owned persistent idle sessions.

Accepted automated load evidence uses 40 read-only nearby-property requests with concurrency 20 followed by a health check. The first fully accepted run after worker tuning completed 40/40 requests successfully and kept the health gate green. The measured latency is recorded as diagnostic evidence rather than a production SLO because Render UAT and Supabase UAT are in different regions.

The remaining Phase 0 closure gate is real APK visual/device end-to-end acceptance using Computer Use across the supported roles and reachable flows. No merge to `main` and no Production change is implied by the automated audit.

## 2026-09-05 — AI development operating system setup

Baseline: `f76b5c15e3f6918a93c4781d051c2703f7a23409`

Prepared persistent project instructions and engineering context for ChatGPT/Codex:

- `AGENTS.md`
- `docs/AI_PROJECT_STATE.md`
- `docs/ARCHITECTURE.md`
- `docs/BUSINESS_RULES.md`
- `docs/WORKFLOWS.md`
- `docs/SECURITY.md`
- `docs/UAT_RUNBOOK.md`
- `docs/DECISIONS.md`
- `docs/AI_TASK_TEMPLATE.md`

Purpose:

- make Git HEAD the first source of truth for future AI sessions
- preserve product constraints across chats
- move feature development toward branch -> PR -> CI -> UAT rather than manual ZIP transfer
- prepare the repository for Codex-driven implementation with product-owner approval gates

No application runtime, backend logic, database schema, or cloud configuration is changed by this documentation setup.

## Previous accepted milestone — Free Services Phase 1

Feature commit: `674b6ef006b3a84a43539f9b3c11b37286e1756f`

CI baseline acceptance commit: `f76b5c15e3f6918a93c4781d051c2703f7a23409`

High-level result:

- free services hub introduced
- paid features disabled in active services journey
- account page reorganized
- backend capabilities drive professional service visibility
- accepted Flutter services-screen hash updated in CI after successful validation
