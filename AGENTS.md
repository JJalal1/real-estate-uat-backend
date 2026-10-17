# AGENTS.md — REAL ESTATE UAT

This file is the operating contract for AI coding agents working in this repository.
Read it before proposing or applying changes.

## 1. Project mode

- October17 Wave6 is IN PROGRESS on latest APK1069, explicitly selected by the owner despite the attached document's1039 label. Read `docs/WAVE6_BASELINE_1069_AR.md`. Use `work/wave6-current-1069`; owner approved uploading this wave's code/tests and running CI. No Wave6 installer is accepted yet. Preserve the source of1069, manual-stop voice, financial history, account/media boundaries and UAT-only scope. Do not infer completion from historical CI69 or a partial checkpoint.

- Current October16 active-wave delivery: APK1069 source `526a87f10a63669c747e3ea967d0128e0e95547c`, PR80 merged as `5d5fe18ac08eb9cf1117509a05f5c82baf5a0935`. Its entire tree equals tested `58d07100918a1383ebc3854d8d7129daae0fd43f`. All five CI69 gates passed:250 Laravel tests (one SQLite-only PostGIS skip covered by the PostgreSQL gate), PostgreSQL17/PostGIS/access contracts, Docker, clean Flutter analysis,196 selected/331 full Flutter tests (overlapping), native release build and APK verification. Focused80 tests passed; all12 inspected synthetic preview hashes match CI69. The current Free Frankfurt deployment is `dep-db989jvbtjjs739q9d4g` at the merge SHA; public smoke checks and a real AI search preserving map constraints passed (200 in1908ms). Read `docs/ACTIVE_WAVE_DISCOVERY_AR.md`. Natural fact-bound copy, lightweight chip/left robot, shared AI/map/save filters,2–4-property comparison, public directory/profile privacy and organized property details with explicit authorized dialer are implemented. No schema, reseed or financial-history changes. Mobile tree `372e6966ed98d7372c76fd514ec11bf0d0e3a99b`; backend tree `640b62ddbc20ddda414152b362f601b4da4b4f10`. APK1069 is locally verified and available; handset/native-map/dialer/microphone acceptance remains open. The development certificate differs from1063; retain local drafts before uninstalling. Do not roll back to an older numbered baseline or infer stable AI availability from one live success.

- Previous October16 reference-video delivery: APK1063 source `2822ab45be21a6a715f0b0bafafce24fe449ff9f`, merged PR78 `807d34330d1d9c4687308d54f55618b29ad2f28e`. All five CI63 gates passed (185 selected/320 full Flutter tests, overlapping), plus35 focused tests. Five corrected synthetic previews match CI exactly and were inspected, including scrolled2.4 controls. In-composer live dictation preserves typed context, manual finish and explicit edited send; partial previews never persist or execute. The existing full-clip fallback remains. Read `docs/VOICE_REFERENCE_1063_DELIVERY_AR.md` and the reference contract. Preserve this accepted voice behavior in later waves.

- Previous owner-approved broker assistant deployment (October16): APK1058 source `2b955f18ea15946d462c1a3c111cda525e724377`, merged PR76 `ddedbf4992ec93eb5da2c1ee574267a475de369e`, live Frankfurt deploy `dep-db91o6ei0phs739ci6eg`. The owner approved merge/UAT deployment at15:42 Asia/Aden. All five CI58 gates passed; the full merge tree exactly matches the tested tree. Read `docs/BROKER_AI_1058_DEPLOYMENT_AR.md` and `docs/BROKER_AI_ASSISTANT_AR.md`. Post-deploy public checks passed; real AI search initially returned503 near25s and then200 in12.8s. Retain honest text fallback and do not claim stable provider/handset acceptance from one success. No new schema or financial/auth/media boundary changes.

- Product: REAL ESTATE.
- Current environment: UAT / staging only.
- Do not create or migrate to Production unless the product owner explicitly requests it.
- Repository: `JJalal1/real-estate-uat-backend`.
- Primary branch: `main`.
- Active private product branch: `work/broker-experience-v1`.
- Previous owner-approved Wave5 merge/UAT deployment (October16): APK1052 source `10ee06afea31c50f3f914d9788de4873bde3db0c`, merged source `c309fa5d2a52a5010850478e551711e60077076b`, live Frankfurt deploy `dep-db8oa4ff3r2c73eqm660`. CI52 is green, the additive native Sai migration is applied, and prior financial history hashes match. Read `docs/WAVE5_1052_DEPLOYMENT_AR.md`. Public health/discovery/Sai checks passed; the live AI provider returned503 at startup and in two real search checks. Do not report AI/handset acceptance as complete or reset data/reseed to address provider availability.
- Earlier owner-approved task (October16): Wave5 on APK1049 source `db378214ade105a7046a2d1069095070ac76f7a4`, branch `work/wave5-baseline-1049`. The owner resolved the attached file's1039 label in favor of current1049. Read `docs/WAVE5_BASELINE_1049_AR.md`. Rental-apartment area/elevator are hidden and position is optional with support identity review; rental requirements use inline chips; native fixed/percentage Sai terms retain financial history; lightweight Home/My Account entries reuse the current search session and manual-stop recording. Preserve owner rates, zero fallback, 20/80 split, payer, retired viewings, private storage and UAT-only boundaries.
- Retained Wave4 baseline: direct-execution handoff, pinned to APK1039 source `998f3456d5dd74b493052376cf0091737c1eaf21`; branch `work/wave4-baseline-1039`. Read `docs/WAVE4_BASELINE_1039_AR.md`. Do not import APK1043 startup retry/cache changes. The owner explicitly retires the viewing/booking journey and notifications in favor of ordinary messages, moves photos/description/optional rental conditions to step3, simplifies step4, and requires manual-stop whole-recording voice with persistent search context. New Sai consent uses the existing post-publication attestation; immutable financial terms/history and rates remain protected. Camera/token storage, account permissions, assets/dependencies, UAT-only and paid/Production boundaries remain. Earlier phase/whole-floor/viewing requirements below are historical where this explicit scope supersedes them.
- Current stack: Flutter Android + Laravel API + PostgreSQL/PostGIS + Supabase Storage + Render UAT + GitHub Actions.

## 2. Source of truth

When information conflicts, use this order:

1. Current Git HEAD / current repository files.
2. Latest successful CI evidence for the relevant change.
3. Live UAT state in GitHub/Render/Supabase when connected and verified.
4. Current documentation in `docs/`.
5. Historical handoff material only for context.

Never treat an old ZIP, snapshot, or chat description as current state if it conflicts with Git HEAD.

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

Do not change these without explicit product-owner approval:

- Do not redesign the architecture from scratch.
- Do not change the role/permission model arbitrarily.
- Laravel/backend authorization is authoritative; Flutter visibility is never a security boundary.
- No broker hierarchy, regional broker exclusivity, master/sub-broker structure, or broker ownership of a region.
- Verified brokers may operate across regions subject to normal workflow and duplicate/review rules.
- Account verification professional types are `owner`, `broker`, and `office`.
- Support work uses a shared queue / claim model. First valid claim wins; backend must prevent double claim.
- Published listings are public; login is not required merely to browse published properties.
- The product is free from the user's perspective: no paid promotion, paid upgrades, marketing packages, or paid service tiers in the active user journey. The October 14 handoff authorizes the editorial Spotlight presentation foundation; plans and prices remain deferred.
- Legacy payment/service infrastructure may remain dormant if deleting it would create unnecessary migration risk.
- Viewing requests start from a specific property, not from a generic top-level service.
- Sensitive storage stays private.
- Property Requests / Researcher Requests / broker matching are deferred and must not be exposed as active launch capabilities unless explicitly re-approved.

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

Identity/selfie/documents are reviewed according to the existing verification workflow. Owner identity is reviewed once; relationship to each property is reviewed independently when required. Selfie capture is camera-only. Other supported documents may use camera or file selection where implemented.

## 7. Support and review rules

- Support agents and support managers are operational roles, not professional property account types.
- Shared items are visible to eligible support staff until claimed.
- Once claimed, a task belongs to the claimant unless backend rules allow manager reassignment/escalation.
- Sensitive private-conversation review requires explicit permission and case context and must be auditable.
- Do not rely on hidden Flutter buttons for authorization.

## 8. Change discipline

For every code task:

1. Inspect current implementation before editing.
2. Identify the smallest coherent scope.
3. Reuse existing entities/workflows instead of creating parallel systems.
4. Preserve API compatibility unless the task explicitly requires a justified API evolution.
5. Add/update backend tests for authorization and persistence behavior.
6. Add/update Flutter tests for UI/contracts/navigation when relevant.
7. Run the narrowest relevant tests first, then required regression checks.
8. Run `git diff --check` when the execution environment supports it.
9. Do not hide a failing test by weakening/removing an assertion unless the old assertion is demonstrably obsolete and the replacement preserves the intended contract.
10. Update project-state/docs if accepted behavior or architecture changes.

## 9. Git and CI policy

- Do not commit directly to `main` for feature work.
- Use a focused branch and Pull Request.
- Keep PR scope small enough to diagnose failures.
- GitHub Actions is an independent gate.
- Flutter changes require a successful APK workflow before UAT acceptance.
- Backend-only changes require backend regression coverage.
- If an accepted-baseline hash changes intentionally, update the guard only after proving the new file is exactly the intended accepted state. Do not disable the guard.
- Do not merge a feature PR until required CI/review checks are green and product-owner approval is present.

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

## 13. Product direction and phase state

The accepted product direction is marketplace-first.

Launch-critical journey:

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Phase 0 is closed.
Phase 1 UX/UI Product Foundation is closed at source/automated-acceptance level.
Phase 2 Listing Journey Hardening is closed at source/automated-acceptance level. Its final automated gate includes Laravel regression, PostgreSQL 17 + PostGIS migration/security/lifecycle acceptance, Flutter analysis/tests, and UAT release APK build/upload.

The next implementation phase is **Phase 3 — Buyer Discovery Completion**.

Phase 3 must reuse the existing public discovery implementation. It should harden cards/map/list/details consistency, public search/filter/sort/bounds/pagination boundaries, similar-property correctness and measured media/performance behavior, and add server/account-bound Favorites with database/API/auth/Flutter/tests. Do not rebuild discovery from scratch.

Later launch-related work includes:
- viewing/booking/conversation integration hardening
- Rental Contracts
- Price Indicators + Property Valuation using one backend data engine
- Real-estate Guide + Legal Documents library
- Production readiness and launch hardening

Real-device subjective visual review is a Beta/launch-readiness gate. Lack of Computer Use/emulator access must not freeze normal engineering work.

## 14. When documentation and code disagree

Code/live behavior wins for current-state facts. Product rules in this file and `docs/BUSINESS_RULES.md` win for intended behavior unless the product owner explicitly changes them. If a discrepancy is found, document it and fix the smallest correct layer before broad expansion.
