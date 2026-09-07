# AI Change Log — REAL ESTATE

Use this as a concise history of AI-assisted engineering milestones. It is not a substitute for Git history.

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

## Next planned milestone

Complete Phase 0 visual/device acceptance. Property Requests / Researcher Requests remain frozen until Phase 0 is closed and a new feature phase is explicitly resumed.
