# AI Project State — REAL ESTATE UAT

Last updated: 2026-10-15

## Home startup recovery — October 15 latency report

The owner reports slow initial home loading and a temporary-server-error screen in APK 1039. Read `HOME_STARTUP_RECOVERY_AR.md`. Read-only public probe CI `38640113092` measured first health 39.999 s, first marketplace 6.708 s, repeat marketplace 0.960 s and later requests 0.466–0.518 s, all HTTP 200. The reported 5xx was not reproduced; cold startup is consistent with this evidence, not a proven explanation of every failure. Render workspace selection was unanswered, so internal account logs/metrics were not accessed.

The focused `work/home-startup-recovery` change adds bounded UAT recovery only for anonymous home reads, cancellation on disposal/route departure, successful public feed retention for 45 s keyed by region/type, existing revision/manual invalidation, and clear slow-load/failed-refresh feedback. All five CI 43 jobs (`38646662876`) passed at `4296aa06f9735f9bc63d12f235155fbabf46d705`, including sixteen new cases, strict analysis, full Flutter/Laravel/PostgreSQL regression, runtime, compiled endpoint, APK 1043 build and installer verification. No backend, SQL, infrastructure plan, data, voice/session, native permission, dependency or asset change is included. No instant cold-start or handset acceptance is claimed.

Draft PR 71 records this focused change. The user explicitly approved the named APK 1043/private-GitHub-log/existing-private-Drive delivery route at 02:59 Asia/Aden on October 15, resolving the earlier automatic-review rejections. Authorized private transfer run `38657402759` at `c5f0a803c572160842afc39676060ab4f73e7f46` passed all 32 segments. The downloaded original `RealEstate-1043.apk` matches the verified CI digest; local ZIP CRC, CMS signature, all 715 signed payload entries, package/version, three compiled Frankfurt API architectures and five original Manrope fonts passed. No installer bytes were rebuilt or modified during transport. The saved file replaced the prior private Drive installer in place; readback verified its 1043 name, exact size and unchanged owner plus previously approved reader, without public sharing. Private delivery account/file identifiers remain in the local handoff, outside this document. No merge, paid resource, backend deployment or data mutation was performed.

Metadata-only run `38649078801` independently passed and read the original verified CI evidence: APK 1043 is 49,250,885 bytes with SHA-256 `847ad17f84d77eeec2df2e473861ee1a1d6d062f76635fc807c32bb6041c9217`. It emitted only version, source, size and digest, without installer/preview/raw-log payload. Local installer validation subsequently passed after explicit delivery consent. Its development certificate `7607e044380715eb7d6e46ba9c2d79d924e087498c13a4413ba6ce209919fa16` differs from APK 1039; save unsent local drafts and uninstall the old app before installing 1043. Handset acceptance and real handset latency remain pending.

## In-app search dictation — October 14 evening correction

The product owner rejected the external Google recognition Activity in APK 1035. Read `VOICE_IN_APP_AR.md`. The replacement is implemented and all five Broker Experience CI 39 jobs (`38619452813`) passed at `998f3456d5dd74b493052376cf0091737c1eaf21`. It keeps microphone motion, level-responsive waves, partial transcript, finish/cancel and final inference inside the existing AI search surface. Home text/voice searches update shared session chips and inline real results without automatic navigation. A user may explicitly open all results/filters. No TTS or background capture is added. The native handler requires microphone permission and recognition-service visibility; camera/token code, dependencies and backend remain unchanged. Mobile tree: `909b5b1626802223456ac2f83397be518cb58c82`; backend tree is still `d3c3b49139fb69c7873c2b223100ffc544fca59f`, so no Laravel deployment or data changes were needed.

APK 1039 is now available as `real-estate-uat-1039.apk`: 49,226,543 bytes, SHA-256 `84de777f97c29ea3c6f2301f2432a8a35c40f11bf128c48e9a8fe5e7fea4dde1`. The user explicitly approved transfer through additional private GitHub logs on October 14 at 22:43 Asia/Aden, resolving the earlier automatic-review rejection. Read-only delivery run `38626129326` at `ca5eff5cf6828d454669dc3500772d49db915341` passed all 32 installer segments and the preview job. The downloaded original installer matches the verified CI digest; local ZIP CRC, CMS signature, all 715 signed entries, package/version, three compiled Frankfurt API architectures and five original Manrope fonts passed. RECORD_AUDIO is the only added permission versus APK 1035, and native SpeechRecognizer/RecognitionListener APIs and service visibility are present. The file is saved for user download. Its development certificate `315a7db0fe23087dce79e3f479f28dd6b1ae053a64d596116c14661d37f2bf57` differs from APK 1035; save unsent local drafts and uninstall the previous app before installing 1039. No installer bytes were rebuilt or modified during transfer. Reference-video and handset acceptance below remain open.

The approved, materially safer `review/voice-ui-39` branch emits only two synthetic PNG previews and small build metadata, no installer bytes. Its run `38623531374` passed. Both current-source previews were hash-verified and inspected with the actual bundled Arabic/Manrope/icon fonts at ordinary and enlarged text sizes; no overflow was found. The Houzi video and newly referenced screenshot are not available in this conversation; motion comparison and real-handset microphone acceptance remain open. The APK 1035 evidence below is historical and does not imply that the external voice UI is accepted.

## Wave3 AI/design addition — UAT installer ready

Read `WAVE3_AI_DESIGN_AR.md`. The complete October 14 handoff has been implemented: Laravel-only Gemini, persistent text/voice/manual search, regional home sections, editorial Spotlight foundation, card galleries, a responsive professional tool grid, reviewed listing suggestions and public property questions. The earlier marketplace/account/UAT behavior remains. Automated verification and UAT rollout are complete; handset and reference-video acceptance remain open.

The delivered APK is `real-estate-uat-1035.apk`, built from `d6016cb3b9274a36ad728c53c9998aa2bd46e0fc` by successful Broker Experience CI 35 (`38492343240`). SHA-256 is `af8f4d567ca4413282b4433812366412bb5e9ed9ebaf66cd4a474f02910000cc`; size is 49,179,705 bytes. Local checks passed ZIP CRC, CMS signature and all 715 signed payload digests, package/version, three compiled Frankfurt API architectures and five original Manrope fonts. Its development signing certificate differs from APK 1026/1019: save unsent local drafts and uninstall the older app before installing it.

The deployed backend source is `965702d9751456fa7efd8f2bc74b7d6512072d13`; Broker Experience CI 36 (`38495247339`) passed all five jobs, including the complete Laravel/PostgreSQL/PostGIS and Flutter/APK gates. Only three backend PHP files changed after APK 1035's source; both sources have the identical mobile tree `b05bab2c9e4de7520c2028f15afcf63f91ee99c2`. The fix uses the official generateContent `APPLICATION_JSON` enum and sanitized probe failure codes. The existing Free Frankfurt Render deployment `dep-db7dmeq5b2lc73fi1d40` is live; its actual Gemini connection probe passed at `2026-10-14T01:31:44Z`, with the key retained on the server. Later documentation-only commits do not change this tested application code or the live source.

Post-rollout Frankfurt data still contains 15 users, 27 properties/photos, 11 deals, 10 ratings and 11 receivables. The one-time design seed adds only six explicit elevator facts and three editorial Spotlight samples. Protected operational users/roles/profiles/documents match their pre-rollout hashes; all 12 immutable-delete guards remain enabled. The daily AI aggregate has RLS and no direct PUBLIC/anon/authenticated grants. Advisors report only intentional deny-all RLS INFO and unused-index INFO.

The three newly named reference videos are not attached. Five embedded images and generated test previews were reviewed; no handset acceptance is claimed. Professional tools, ownership, review and financial authority remain on Laravel. Earlier UAT cleanup must not repeat. CI permissions remain read-only. The installer was transferred through bounded private CI log segments, verified locally and made available; no runner repository write or release publication is enabled. Draft PR 70 contains the final evidence. No merge, Production rollout or paid resource is authorized.

## Earlier Wave3 marketplace — preserved behavior

The earlier completed task `docs/WAVE3_MARKETPLACE_AR.md` defines eight basic listing types, whole-floor scope inside apartment details, one personal listing for modern non-professional accounts, and approved broker/office-only work tools. Owner verification and private per-property relationship evidence remain required. The earlier six broker conveniences and customer-paid commission policy are retained.

Wave3 includes an explicitly authorized, one-shot cleanup of the exact legacy Frankfurt UAT fixture identities followed by 11 fictional marketplace personas and 27 listings. The implementation preserves operational accounts/roles/verification data, verifies a private sanitized backup, restores immutable delete triggers in the same transaction, and refuses Production or another Supabase project. See that task document for the scope and fixture entry phones. A successful seeding marker prevents any repeat cleanup or recreation of legacy accounts.

Draft PR 70 is the evidence index for the latest exact source SHA, green CI, APK, and Frankfurt deployment. Earlier APK 1019 corresponds to second-round baseline `2f05967397e1921fc55927111f57b0445f0c7e45`; it does not contain Wave3. APK 1026 contains the earlier marketplace work but not the AI/design addition. Automated checks do not imply handset acceptance. Artifact-storage quota is handled by bounded private read-only CI log transport after all required tests and APK verification pass.

## Earlier broker UAT work — history

The private feature branch is `work/broker-experience-v1`. Its completed six-convenience baseline is commit `aa9af22660c641781b43ef024691aa25585f2bbd`, Broker Experience CI 12 (`38314145189`), APK 1012 and the same live Frankfurt UAT deploy (`dep-db6lniivcj2c738g020g`). Handset acceptance for that build is not recorded here as completed.

The product owner's October 13 second-round UX refinement is the preceding work package, documented in `docs/UX_REFINEMENT_ROUND2_AR.md`. It deliberately changes the advertiser's initial page to the marketplace, refines the four-step dynamic listing editor and inline customer-paid commission, quiets unread notifications, and adds a limited editable assisted-search flow using actual public API results. Literal template parity and the older five-step/initial-dashboard decisions are superseded within this authorized scope; the original assets, fonts, dependencies, native code, permissions, review and immutable financial history remain protected.

The latest exact commit, CI results, APK identity and rollout evidence belong to Draft PR 70 and its matching workflow artifacts. A candidate is not accepted on a handset merely because it builds. The supplied Houzi screenshots were reviewed; the named MP4 was not attached and no claim is made that it was watched. See the new task document for manual acceptance and the remaining reference review.

This work does not authorize merging into main or protected reference branches, or creating production/paid resources. Historical phase/environment statements below are retained as history and do not override this active branch, current code or fresh CI evidence.

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
