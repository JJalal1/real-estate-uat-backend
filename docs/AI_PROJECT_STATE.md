# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-08

## Current gate — Phase 4 closure candidate

Phase 3 — Buyer Discovery Completion + Server-side Favorites is CLOSED by explicit product-owner acceptance after successful automated gates and real-device Android acceptance.

Phase 4 — Messaging + Viewing Journey Hardening is the active engineering phase and is now an automated/UAT-database closure candidate.

Branch: `phase4/messaging-viewing-hardening`
Draft PR: #17 targeting `phase1/ux-product-foundation`
Draft UAT integration PR: #18 targeting `audit/system-stabilization`
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

Final-head automated evidence is COMPLETE:
- accepted Phase 4 CI head: `fadac78ad5ce3abb260c5db468ea175d2d9a6a54`;
- Phase 4 Messaging Viewing CI run #48 / `34275753072`: SUCCESS;
- full Laravel regression suite: SUCCESS;
- explicit Phase 4 Laravel messaging/viewing contract: SUCCESS;
- PostgreSQL 17 + PostGIS complete migration chain: SUCCESS;
- PostgreSQL security/schema regression + Phase 4 acceptance: SUCCESS;
- `flutter analyze`: SUCCESS;
- full Flutter test suite: SUCCESS;
- compile-time UAT endpoint verification: SUCCESS;
- release UAT APK build/upload: SUCCESS;
- APK artifact: `real-estate-phase4-uat-apk-48`;
- artifact digest: `sha256:040118c60d24b83156842ff83d1c6816f4c1b95279cc68f0fa62a1438127bcbc`.

The earlier zero-step GitHub Actions failures were runner/quota behavior while the repository was private, not application test failures. After the product owner changed repository visibility to public, hosted runners executed normally and exposed one stale source-location test; that test was corrected to follow the extracted notification-destination contract, after which run #48 passed all final-head gates. The repository is currently public; secrets and credentials must remain outside Git history.

Supabase UAT Phase 4 schema evidence is COMPLETE:
- migration `harden_phase4_messaging_viewings` is already recorded in UAT;
- `private_messages.client_message_id` is nullable `varchar(100)`;
- unique `(thread_id, sender_user_id, client_message_id)` index exists;
- RLS remains enabled;
- no direct `PUBLIC` / `anon` / `authenticated` table grants were found;
- Security Advisor shows only the intentional deny-all `rls_enabled_no_policy` INFO;
- Performance Advisor shows existing `unused_index` INFO only; no index deletion is justified without workload evidence.

Render UAT is NOT yet verified running Phase 4. The last confirmed service source is `audit/system-stabilization` with auto-deploy disabled. PR #18 is the prepared UAT-only integration path. Successful CI and Supabase verification do not by themselves prove the Render runtime is on the Phase 4 code.

No merge to `main` is approved and no Production deployment is implied. PR #17 and PR #18 remain unmerged until their respective next actions are executed.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Current repository visibility: public
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
- Phase 2 regression on the same accepted head: SUCCESS;
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

Completed closure gates:
- final-head Phase 4 CI passed Laravel + PostgreSQL 17/PostGIS + Flutter tests;
- final-head UAT release APK artifact built and uploaded;
- Supabase UAT Phase 4 migration/schema/security verification completed.

Still required before final product-owner Phase 4 acceptance:
- integrate Phase 4 into the UAT runtime branch and deploy Render UAT;
- verify Render `/api/health` and the live property-linked messaging/viewing journey;
- install/test the Phase 4 Android candidate on a real device;
- explicit product-owner Phase 4 acceptance after device verification.

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
