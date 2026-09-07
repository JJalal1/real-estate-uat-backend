# AGENTS.md — REAL ESTATE UAT

This file is the operating contract for AI coding agents working in this repository.
Read it before proposing or applying changes.

## 1. Project mode

- Product: REAL ESTATE.
- Current environment: UAT / staging only.
- Do not create or migrate to Production unless the product owner explicitly requests it.
- Repository: `JJalal1/real-estate-uat-backend`.
- Primary branch: `main`.
- Current stack: Flutter Android + Laravel API + PostgreSQL/PostGIS + Supabase Storage + Render UAT + GitHub Actions.

## 2. Source of truth

When information conflicts, use this order:

1. Current Git HEAD / current repository files.
2. Latest successful Result/CI evidence for the relevant change.
3. Live UAT state in GitHub/Render/Supabase when connected and verified.
4. Current documentation in `docs/`.
5. Historical handoff material only for context.

Never treat an old ZIP, old snapshot, or old chat description as the current source if it conflicts with Git HEAD.

## 3. Required read order for a new task

Read at least:

1. `AGENTS.md`
2. `docs/AI_PROJECT_STATE.md`
3. `docs/ARCHITECTURE.md`
4. `docs/BUSINESS_RULES.md`
5. `docs/WORKFLOWS.md`
6. `docs/SECURITY.md`
7. the actual files touched by the task

For a substantial change, also read `docs/UAT_RUNBOOK.md`, `docs/DECISIONS.md`, and `docs/AI_TASK_TEMPLATE.md`.

## 4. Hard product constraints

Do not change these without explicit product-owner approval and evidence that the change is required:

- Do not redesign the architecture from scratch.
- Do not change the role/permission model arbitrarily.
- Laravel/backend authorization is authoritative; Flutter visibility is never a security boundary.
- No broker hierarchy, regional broker exclusivity, master/sub-broker structure, or broker ownership of a region.
- Verified brokers may operate across regions subject to the normal workflow and duplicate/review rules.
- Account verification professional types are `owner`, `broker`, and `office`.
- Support work uses a shared queue / claim model. First valid claim wins; backend must prevent double claim.
- Published listings are public; login is not required merely to browse published properties.
- The product is free from the user's perspective: no paid promotion, paid featured listings, paid account upgrades, paid marketing packages, or paid service tiers in the active user journey.
- Legacy payment/service infrastructure may remain dormant if deleting it would create unnecessary migration risk.
- Viewing requests start from a specific property, not from a generic top-level service.
- Sensitive storage stays private; never make the bucket public just to simplify UAT.

## 5. Current roles and account concepts

Core UAT personas:

- regular user
- unverified broker
- verified broker
- support agent
- support manager
- platform owner / super admin

The platform owner may grant roles/permissions according to the existing backend model. Do not create random standalone test accounts for every internal permission unless requested.

## 6. Account verification rules

The basic account remains a browsing/search/buyer account after phone verification and profile completion.
A user can request a professional identity:

- owner
- broker
- real-estate office

Identity/selfie/documents are reviewed according to the existing verification workflow. Owner identity is reviewed once; the relationship to each property is reviewed independently when required. Selfie capture is camera-only. Other supported documents may use camera or file selection where implemented.

## 7. Support and review rules

- Support agents and support managers are operational roles, not professional property account types.
- Shared items are visible to eligible support staff until claimed.
- Once claimed, a task belongs to the claimant unless backend rules allow manager reassignment/escalation.
- Sensitive private-conversation review requires an explicit permission and case context and must be auditable.
- Do not rely on hidden Flutter buttons for authorization.

## 8. Change discipline

For every code task:

1. Inspect the current implementation before editing.
2. Identify the smallest coherent scope.
3. Reuse existing entities/workflows instead of creating parallel systems.
4. Preserve API compatibility unless the task explicitly requires an API evolution.
5. Add/update backend tests for authorization and persistence behavior.
6. Add/update Flutter tests for UI/contracts/navigation when relevant.
7. Run the narrowest relevant tests first, then required regression checks.
8. Run `git diff --check`.
9. Do not hide a failing test by weakening/removing the assertion unless the old assertion is demonstrably obsolete and the replacement test preserves the intended contract.
10. Update project-state/docs if the accepted behavior or architecture changed.

## 9. Git and CI policy

- Do not commit directly to `main` for feature work.
- Use a focused branch and Pull Request.
- Keep PR scope small enough to diagnose failures.
- GitHub Actions is an independent gate, not a formality.
- Flutter changes require a successful APK workflow before UAT acceptance.
- Backend-only changes do not require a new APK unless the mobile contract/build-time configuration changes.
- If an accepted-baseline hash changes intentionally, update the guard only after proving the new file is exactly the intended accepted state. Do not disable the guard.
- Do not merge a feature PR until required CI and review checks are green and product-owner approval is present.

## 10. UAT deployment rules

- Render is the Laravel UAT runtime.
- Supabase provides UAT PostgreSQL/PostGIS and private storage.
- Do not delete the existing Render UAT service while testing a replacement region/service.
- Do not create a paid cloud resource without explicit approval.
- If investigating latency, measure network/region/database/API behavior before adding caching or rewriting queries.

## 11. Secret handling

Never commit, print, request in chat, or add to generated artifacts:

- `.env`
- `APP_KEY`
- DB passwords / credential-bearing DB URLs
- Supabase server/service secrets
- UAT OTP code
- WhatsApp secrets
- private keys
- keystore secrets

Agents may verify that an environment-variable name exists, but should not require its value to be pasted into chat.

## 12. UAT OTP rule

UAT may use allowlisted test OTP behavior. Production must never allow the UAT test-OTP backdoor. Any auth change must preserve an explicit staging-only guard.

## 13. Current product direction

The most recent accepted product direction is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Current Phase 1 focuses on UX/UI product foundation and information architecture before broad feature expansion.

Accepted navigation direction is documented in `docs/PHASE1_ACCEPTED_IA.md`.

Property Requests / Researcher Requests / matching are deferred and must not drive primary navigation or the launch-critical roadmap unless the product owner explicitly re-approves them later.

Later launch-related work includes:

- server-side Favorites
- viewing/booking/conversation integration hardening
- Rental Contracts
- Price Indicators + Property Valuation using one backend data engine
- Real-estate Guide + Legal Documents library
- Production readiness and launch hardening

Before implementing any later feature, confirm `docs/AI_PROJECT_STATE.md`, `docs/PHASE1_UX_PRODUCT_FOUNDATION.md`, `docs/PHASE1_ACCEPTED_IA.md`, and current Git HEAD.

## 14. When documentation and code disagree

Code/live behavior wins for current-state facts. Product rules in this file and `docs/BUSINESS_RULES.md` win for intended behavior unless the product owner explicitly changes them. If a discrepancy is found, stop broad changes, document the mismatch, and fix the smallest correct layer.
