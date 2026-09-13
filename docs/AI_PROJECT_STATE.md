# AI Project State — REAL ESTATE UAT

Last updated: 2026-09-09

## Current gate — Phase 4 CLOSED; next work is product-owner priority intake

Phase 3 — Buyer Discovery Completion + Server-side Favorites is CLOSED by explicit product-owner acceptance after successful automated gates and real-device Android acceptance.

Phase 4 — Messaging + Viewing Journey Hardening is CLOSED by explicit product-owner acceptance after successful automated gates, Supabase UAT verification, Render UAT deployment, and real-device Android acceptance.

Phase 4 tracker: #16 — CLOSED as completed.
Phase 4 PR: #17 -> `phase1/ux-product-foundation` — merged.
UAT integration PR: #18 -> `audit/system-stabilization` — merged.
Canonical Phase 4 contract: `docs/PHASE4_MESSAGING_VIEWING_HARDENING.md`.

There is deliberately no automatically active “Phase 5” after Phase 4. The product owner explicitly deferred the previously discussed later roadmap items and intends to prioritize other work first. Future work must be selected from new product-owner priorities rather than inferred from old numbering.

Current Phase 4 accepted outcome:
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
- dedicated Phase 4 Laravel + PostgreSQL 17/PostGIS + Flutter + release APK CI is green.

Final Phase 4 automated evidence:
- final documented CI head: `1513399f5c0bb6a8d916c5515cba095389c3c2df`;
- Phase 4 Messaging Viewing CI run #50 / `34276623699`: SUCCESS;
- full Laravel regression suite: SUCCESS;
- explicit Phase 4 Laravel messaging/viewing contract: SUCCESS;
- PostgreSQL 17 + PostGIS complete migration chain: SUCCESS;
- PostgreSQL security/schema regression + Phase 4 acceptance: SUCCESS;
- `flutter analyze`: SUCCESS;
- full Flutter test suite: SUCCESS;
- compile-time UAT endpoint verification: SUCCESS;
- release UAT APK build/upload: SUCCESS;
- APK artifact: `real-estate-phase4-uat-apk-50`;
- artifact digest: `sha256:6a1903236fff5abc966fdb4b4d452b2b022fe22db3f28f79add808438a0af665`.

The earlier zero-step GitHub Actions failures were runner/quota behavior while the repository was private, not application test failures. After the product owner changed repository visibility to public, hosted runners executed normally. The repository is currently public; secrets and credentials must remain outside Git history.

Supabase UAT Phase 4 schema evidence is COMPLETE:
- migration `2026_09_08_010000_harden_phase4_messaging_viewings` is recorded in Laravel migration history;
- `private_messages.client_message_id` is nullable `varchar(100)`;
- unique `(thread_id, sender_user_id, client_message_id)` index exists;
- RLS remains enabled;
- no direct `PUBLIC` / `anon` / `authenticated` table grants were found;
- Security Advisor shows only the intentional deny-all `rls_enabled_no_policy` INFO;
- Performance Advisor shows existing `unused_index` INFO only; no index deletion is justified without workload evidence.

During the first Render rollout, `property_favorites` already existed while its Laravel migration-history row was missing. The live table was verified to match the repository migration exactly, including columns, PK, cascading FKs, unique key, supporting index, RLS, and deny-all direct grants. Only the missing Laravel bookkeeping row was inserted; no table/data DDL was reapplied and no user data was modified.

Render UAT Phase 1–4 runtime evidence is COMPLETE:
- UAT integration merge commit: `dd9e06d2c613a5322bb9ab34e2e1f869c2d924de`;
- Render service: `real-estate-uat-api`;
- successful deploy: `dep-dag7gkmk1f9s738b0tb0`;
- deploy status: `live`;
- Cloud UAT environment check passed;
- Laravel reported `Nothing to migrate` after bookkeeping reconciliation;
- Render `/api/health` checks returned HTTP 200 repeatedly during rollout;
- no error-level Render logs were recorded from the successful retry start through post-live verification.

The product owner then installed/tested the Phase 4 Android candidate and explicitly accepted Phase 4 on 2026-09-09.

No merge to `main` is approved and no Production deployment is implied.

## Current repository / environment

- Repository: `JJalal1/real-estate-uat-backend`
- Current repository visibility: public
- Primary branch: `main`
- Integration branch: `phase1/ux-product-foundation`
- UAT runtime branch: `audit/system-stabilization`
- Last completed feature branch: `phase4/messaging-viewing-hardening`
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

Phase 4 — Messaging + Viewing Journey Hardening is CLOSED and ACCEPTED.

Canonical journey:

`published property -> contact/conversation -> message -> viewing request -> confirm/reschedule/reject/cancel -> viewing -> complete`

Completed closure gates:
- final-head Phase 4 CI passed Laravel + PostgreSQL 17/PostGIS + Flutter tests;
- final-head UAT release APK artifact built and uploaded;
- Supabase UAT Phase 4 migration/schema/security verification completed;
- Phase 1–4 stack deployed successfully to Render UAT;
- Render runtime health and startup evidence verified;
- real Android device acceptance completed by the product owner;
- Issue #16 closed as completed;
- PR #17 merged into the integration branch only;
- PR #18 merged into the UAT runtime branch only.

## Current product direction

REAL ESTATE is marketplace-first.

Launch-critical journey currently established through viewing:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> favorite/share/contact -> property conversation -> viewing`

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

## Deferred / future backlog — not the next automatic phase

The following work is preserved for later and must not be started merely because Phase 4 is closed:
- rental contracts and in-app agreement workflow;
- price indicators and valuation using eligible published platform data only;
- Real-estate Guide and Legal Documents library;
- Production/security/operations readiness;
- closed beta -> soft launch -> public launch.

Property Requests, Researcher Requests, and broker-driven request matching also remain deferred unless explicitly re-approved by the product owner.

The product owner explicitly stated on 2026-09-09 that there are other priorities to complete before the preserved future backlog above. The next work package must therefore be defined from those new priorities rather than from old phase numbering.

## Execution model

This ChatGPT session owns engineering work executable through available repository/cloud tools: roadmap decomposition, GitHub changes, CI review, Laravel/API/database/security work, Render/Supabase verification, Flutter source changes, tests, and documentation.

Real-device subjective visual acceptance remains a manual/Beta gate when an actual device is required. Lack of Computer Use must not freeze normal development.

## Update rule

Whenever accepted behavior, roadmap, architecture, or product direction changes, update this file and the relevant workflow/decision/changelog docs. Current Git/code and explicit newer product-owner decisions outrank stale historical documentation.
