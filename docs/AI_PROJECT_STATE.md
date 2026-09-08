# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current gate — Phase 4 closure candidate

Phase 3 — Buyer Discovery Completion + Server-side Favorites is CLOSED by explicit product-owner acceptance after successful automated gates and real-device Android acceptance.

Phase 4 — Messaging + Viewing Journey Hardening is the active engineering phase.

Branch: `phase4/messaging-viewing-hardening`
Draft PR: #17 targeting `phase1/ux-product-foundation`
Draft UAT integration PR: #18 targeting `audit/system-stabilization` — do not merge until final-head Phase 4 CI executes and passes.
Canonical Phase 4 contract: `docs/PHASE4_MESSAGING_VIEWING_HARDENING.md`

Current Phase 4 source outcome:
- one property-linked conversation system retained; no parallel chat/viewing implementation;
- concurrent property conversation opens reuse the same thread;
- participant-only normal private-message access retained;
- support private-content access remains limited to the reported-conversation permission/audit workflow;
- retry-safe private-message delivery using `client_message_id`, including conflict rejection when one logical key is reused for different content;
- bounded newest-first conversation history with older-message pagination;
- read/unread state remains server-authoritative;
- new contact/viewing is blocked for unpublished listings while existing participant conversation/history remains available with an explicit unavailable-listing state;
- viewing state transitions run through backend-authoritative transactions/locks and schedule-conflict checks;
- advertiser reschedule requires requester acceptance; requester reschedule requires advertiser confirmation;
- an advertiser cannot self-confirm or reject its own pending replacement-time proposal;
- an authorized development manager who proposes a replacement time for an unassigned unit viewing becomes the host when the requester accepts;
- terminal booking states are not reopened by normal state actions;
- viewing lifecycle notifications open the exact booking while new-message notifications open the exact property-linked conversation;
- role-aware Arabic pending-reschedule labels/actions are implemented;
- dedicated Phase 4 Laravel + PostgreSQL 17/PostGIS + Flutter + release APK CI exists.

Automated evidence available during implementation:
- an earlier Phase 4 gate passed the full Laravel regression and PostgreSQL 17/PostGIS migration/security + Phase 4 acceptance on an earlier source head;
- later source changes added notification-destination, state-edge, CI-de-duplication, and documentation hardening, so final-head CI is still required;
- the latest Phase 4 GitHub Actions attempts fail before runner assignment (`runner_id: 0`, no job steps), rather than from a Laravel/PostgreSQL/Flutter test failure;
- closed Phase 1/2/3 workflows now skip later-phase PRs so Phase 4 is the only pipeline requesting runners for the active branch.

Supabase UAT Phase 4 schema evidence is COMPLETE:
- migration `harden_phase4_messaging_viewings` is already recorded in UAT;
- `private_messages.client_message_id` is nullable `varchar(100)`;
- unique `(thread_id, sender_user_id, client_message_id)` index exists;
- RLS remains enabled;
- no direct `PUBLIC` / `anon` / `authenticated` table grants were found;
- Security Advisor shows only the intentional deny-all `rls_enabled_no_policy` INFO;
- Performance Advisor shows existing `unused_index` INFO only; no index deletion is justified without workload evidence.

Render UAT is NOT running Phase 4 yet. The service remains on `audit/system-stabilization` with auto-deploy disabled. PR #18 is prepared as the UAT-only integration path, but it must remain Draft until final-head Phase 4 CI can execute and pass.

No merge is approved. PR #17 and PR #18 remain Draft/unmerged. No Production deployment is implied.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Primary branch: `main`
- Integration branch: `phase1/ux-product-foundation`
- UAT runtime branch: `audit/system-stabilization`
- Current feature branch: `phase4/messaging-viewing-hardening`
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
6. valid owned property app deep links/share reference;
7. correct property-linked contact entry;
8. Laravel/PostgreSQL/PostGIS/Flutter/APK regression gates;
9. explicit product-owner Android device acceptance.

Accepted Phase 3 automated evidence:
- accepted CI head: `44af494bd3dd586b693903ced5901e9d143f2d90`;
- Phase 3 Buyer Discovery CI run #34 / `34174945119`: SUCCESS;
- Phase 2 regression on the same head: SUCCESS;
- APK artifact: `real-estate-phase3-uat-apk-34`;
- artifact digest: `sha256:3ed8a4f6a8343c6346ff54b6e15a191da9ee32f41901a781ec1edade78cd1631`.

See `docs/PHASE3_BUYER_DISCOVERY.md` for detailed evidence.

## Phase 4 status

Phase 4 — Messaging + Viewing Journey Hardening is IN PROGRESS / closure candidate.

Canonical journey:

`published property -> contact/conversation -> message -> viewing request -> confirm/reschedule/reject/cancel -> viewing -> complete`

Current engineering scope includes:
1. conversation reuse/privacy/report boundaries;
2. idempotent message delivery;
3. newest-first paged history and server read/unread state;
4. listing-unavailable conversation context;
5. backend-authoritative viewing state machine;
6. advertiser-reschedule requester acceptance;
7. overlap/concurrency protection;
8. exact notification targets/app links;
9. Flutter inbox/conversation/viewing UX hardening;
10. dedicated Laravel/PostgreSQL/Flutter/APK acceptance.

Still required before final phase acceptance:
- final-head Phase 4 CI must receive runners and pass Laravel + PostgreSQL 17/PostGIS + Flutter tests;
- final-head UAT release APK artifact must build;
- merge UAT integration PR #18 into `audit/system-stabilization` only after that CI gate;
- manually deploy Render UAT and verify `/api/health` plus the live property-linked messaging/viewing journey;
- real Android acceptance before final product-owner Phase 4 closure/beta readiness.

Current external blocker:
- recent Phase 4 GitHub-hosted jobs fail before any workflow step executes, with no assigned runner;
- GitHub's public Actions status is operational, so no code regression is inferred from these zero-step failures;
- private-repository Actions usage is subject to the repository owner's plan minutes/storage/budget. The available repository connector does not expose account Billing/Usage, so the exact account-level quota/budget reason is not yet observable programmatically.

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
