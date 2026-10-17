# AI Project State — REAL ESTATE UAT

## Wave6 reviewed implementation and UAT rollout — APK1076

The owner requested completion through reviewed installer delivery, using1069 as the baseline. Read `WAVE6_BASELINE_1069_AR.md`. Final source `493cc09ebc8e544dc545b5dd84710ab7f4af4dbd` passed all five CI76 jobs (`39076536548`) and focused9 (`39076536560`). PR82 merged as `22569181f1c93bf78ceda8be0eb7ca5721186fe5`; its complete tree is exactly the tested `95826858e1576aef9dc8e78c6b3fac5d42cbda2c`. Mobile tree `46433748ff25f7cbf5af24f37fe3a56a501a5e3a`; backend tree `b1122103296b4e5fa04113cd72c2180422a522bf`. Later documentation-only handoff changes preserve both.

Implemented: one generated property schema; account-scoped partial drafts/private photos/revisions; reviewed manual-stop voice and missing-fields completion; inline factual description with late-response protection; policy-derived compact Sai; dynamic factual comparison; one list/map journey cleared on full exit; data/location home and add-house action; existing private broker conversations and distinct closed/deal counts. Review found and fixed a missing draft key in rental-condition assistance, with owner API and explicit-review UI regressions.

Validation passed260 Laravel tests (one SQLite-only PostGIS skip covered on PostgreSQL),106 PostgreSQL/PostGIS tests without skips,25 focused Flutter tests,356 full Flutter tests, strict analysis, Docker, native APK build and verification. Focused/full Flutter suites overlap. All18 inspected normal/2.4 Arabic synthetic preview hashes match corrected focused9 and CI76; they do not establish native-map or microphone acceptance.

Existing Free Frankfurt UAT deploy `dep-db9vuqnbtjjs73d8m5o0` at the merge SHA became live2026-10-17T23:07:14Z. The additive account-draft migration is applied; RLS is enabled, policies intentionally deny direct access, anon/authenticated table and sequence grants are denied, storage remains private and24 immutable guards remain enabled. All15 financial table counts and sorted-row fingerprints match the immediate predeployment snapshot. No reseed, Production, paid resources, assets/dependencies or native Android changes.

Public deployment smoke `39077874142` passed18 checks for health/database/PostGIS, discovery, privacy, Sai, marketplace, broker profiles, authentication and invalid filter/voice requests. One follow-up `39078303916` also passed. Real AI search returned503 (`ai_unavailable`) in both checks, after20288ms and3149ms; fallback was checked, provider success and constraint-preservation were not established live. Do not label provider availability complete or infer success from the workflow's allowed fallback. Physical handset/native MapLibre/microphone acceptance remains OPEN.

Original `real-estate-uat-1076.apk`:49,364,423bytes, SHA256 `a6c7cae5b5974b32d1066b9e2fa01b7ee26d99d17adbb4cf8458d493f070a7ad`. Native apksigner plus local ZIP CRC, CMS signature/all715 signed payloads, package/version1076, three compiled Frankfurt API architectures,145 original assets and five original fonts passed. Delivery run `39077631697` transferred the original bytes without rebuilding/re-signing. The development certificate differs from1069; save local unsent drafts before uninstalling if direct update is rejected.

Last updated: 2026-10-18 (Asia/Aden)

## Active-wave discovery and listing presentation delivered — APK1069

Read `ACTIVE_WAVE_DISCOVERY_AR.md`. Source `526a87f10a63669c747e3ea967d0128e0e95547c`, CI69 (`38958017457`) and merged PR80 (`5d5fe18ac08eb9cf1117509a05f5c82baf5a0935`) share the exact tested full tree `58d07100918a1383ebc3854d8d7129daae0fd43f`. All five gates passed, including250 Laravel tests, PostgreSQL17/PostGIS/access checks, Docker, clean static analysis,196 selected/331 full Flutter tests (overlapping), native build and installer verification. Focused80 tests and12 hash-matched synthetic screen previews cover ordinary/enlarged Arabic text.

The current Free Frankfurt UAT deploy is `dep-db989jvbtjjs739q9d4g` at the merge SHA. Post-deployment health, discovery, public profile, privacy, Sai, polygon/rental-currency validation, contact authentication and existing voice-route validation passed in `38960625251`. One real AI request returned200 in1908ms and preserved the map/source constraints; this does not establish persistent provider availability. No migration, reseed, account cleanup or immutable financial-history change occurred. The prior in-composer voice behavior is retained.

APK1069 is49,409,792 bytes, SHA256 `7a3c35828fa4a5047ae7b7c45775bb6ad01c9020528a5268de51ebb459642d9c`. Its original bytes, ZIP CRC, CMS signature/all715 signed payloads, package/version, three compiled Frankfurt API architectures, five original fonts and native dialer/unchanged permissions passed local verification. Its development certificate differs from1063: retain local drafts before uninstalling. Physical handset, native map, dialer and microphone acceptance remain open. The tested mobile/backend trees are `372e6966ed98d7372c76fd514ec11bf0d0e3a99b` and `640b62ddbc20ddda414152b362f601b4da4b4f10` respectively; later evidence-only documentation changes do not change this application source.

## Previous reference voice interaction delivered — APK1063

The supplied19.4-second reference is implemented on source `2822ab45be21a6a715f0b0bafafce24fe449ff9f`, PR78 merged as `807d34330d1d9c4687308d54f55618b29ad2f28e`. Its complete tree equals tested `f571e2b3e91106b6e9b8393c9c2924afd70d94be`. All five CI63 jobs (`38908197056`) passed, including185 selected/320 full Flutter tests (overlapping), strict analysis, native release build and APK verification. Focused35 tests passed in `38908756343`. Five corrected synthetic preview hashes match both runs and were inspected at ordinary/large scales, including scrolled2.4 controls. Read `VOICE_REFERENCE_1063_DELIVERY_AR.md` and `VOICE_REFERENCE_20261016_AR.md`.

Speech stays in the original search/listing input, preserves typed context and accumulates finalized segments across pauses. Manual finish leaves editable text; only explicit send interprets it. Preview hypotheses never execute or persist. Cancel/error restores the previous brief and proposals. Devices without a recognition service retain full-clip Laravel transcription; Android dictation can depend on a network service. Actual handset/recognizer/microphone and multi-device acceptance remain open.

Original `real-estate-uat-1063.apk`:49,241,917bytes, SHA256 `a2e5b95f14e52f6edae2b89eaf6340328139e053242634aa14033aad296b4f69`. Local ZIP/CMS/715 signed payloads, package/version, three Frankfurt API architectures, five fonts and compiled native recognition/Arabic/service-visibility checks passed. Certificate differs from1058: preserve unsent drafts before uninstalling if direct update fails. No local rebuild/re-signing.

Mobile tree `e2f0b172f699d8732a2518f5689fca85abae801f`; backend remains `67e01f4d14ef9dedc553147dd90d2319a48443b3`, identical to existing live deploy `dep-db91o6ei0phs739ci6eg` at ddedbf4. No new API/schema/provider key, server deployment, dependency, camera/token, financial/auth or organized Home-section changes. Documentation-only follow-ups retain these application trees;1063 remains the delivered installer. Earlier candidate62 failed one missed cancel tap and exposed hint/label overlap; it was corrected and never delivered.

## Broker draft assistant deployed — APK1058

PR76 source `2b955f18ea15946d462c1a3c111cda525e724377` passed all five CI58 jobs (`38844830294`) with178 selected and313 full Flutter tests. The owner approved the exact merge/UAT deployment on October16 at15:42 Asia/Aden. PR76 merged as `ddedbf4992ec93eb5da2c1ee574267a475de369e`; its complete tree equals the tested tree `5dc682e6afa2f58a8faa9478741a4323fde250c2`. The existing free Frankfurt deploy `dep-db91o6ei0phs739ci6eg` is live since2026-10-16T12:45:26Z. Read `BROKER_AI_1058_DEPLOYMENT_AR.md` for evidence and `BROKER_AI_ASSISTANT_AR.md` for behavior.

The editor now prepares reviewable fields/title/description together, requires copy recomposition after field deselection, preserves the raw brief in scoped local recovery, guides completion using existing requirements, and explicitly copies public ad text. The assistant never writes/publishes properties or modifies financial terms. One transient5xx retry shares the existing deadline and charges each attempt to the persistent UTC budget. Labeled literal-text organization is available in the new draft preparation path when AI is unavailable. No schema, provider/key, Production or paid-resource change occurred.

APK1058 is saved as `real-estate-uat-1058.apk`:49,234,167bytes, SHA256 `94e6af6537f4846c3dc66a18d35f9929f59beab93901ffd8804dfaffc01ee3ae`. ZIP/CMS,715 signed payloads, manifest/version, three Frankfurt API libraries and five original fonts passed locally. The development certificate differs from1052; preserve unsent drafts before uninstalling if the device refuses a direct update. Four corrected Arabic previews, including scale2.4, were hash-verified and inspected.

Live public health/database/PostGIS, property discovery/detail/Sai, both new unauthenticated draft modes401, and invalid audio422 passed. Startup Gemini probe passed. Real search in run38902886782 first returned503 after25.519s; the single verification retry passed with200 in12.810s while retaining the search context. Record both outcomes: provider latency is variable, not established as consistently healthy. The new draft fallback does not imply Gemini success. Authenticated listing preparation is covered by CI; physical handset/microphone, real voice transcription and multi-device publication acceptance remain open.

Application subtrees: mobile `16116c3c81c75feffae6ed22925c5d7c8a5a44f6`, backend `67e01f4d14ef9dedc553147dd90d2319a48443b3`. Documentation-only follow-ups retain both;1058 remains the accepted installer for this code.

## Wave5 deployed — APK1052, baseline1049

The owner selected1049 as this wave's baseline and approved PR74 merge/UAT deployment on October16 at04:55 Asia/Aden. Tested source `10ee06afea31c50f3f914d9788de4873bde3db0c` passed all five CI52 jobs (`38833687176`). PR74 merged as `c309fa5d2a52a5010850478e551711e60077076b`; its entire tree exactly equals the tested tree `105a39d52bad8dd622a6e0cdbc0317a4fa453aba`. The existing free Frankfurt service is live at deploy `dep-db8oa4ff3r2c73eqm660`, finished2026-10-16T02:00:51Z. Read `WAVE5_1052_DEPLOYMENT_AR.md` for the final evidence and open AI-provider issue.

APK1052 is saved as `real-estate-uat-1052.apk`:49,189,662 bytes, SHA-256 `c04da95b848e037728838eb71a73a5c38f924f2a9ad9dc65e43455b228781a15`. ZIP/CMS, all715 signed payloads, package/version, three compiled Frankfurt API libraries and five original Manrope fonts passed locally. The development certificate differs from1049; preserve unsent local drafts before removing the previous app if reinstalling is required.

The native fixed-amount migration applied successfully. All27 prior Sai terms and11 financial snapshots retain their pre-deployment hashes; percentage defaults, RLS, immutable triggers and denied anon/authenticated table privileges remain. `UAT_DEMO_SEED_ENABLED=false` and `UAT_RUN_MIGRATIONS=true` were merged without replacing secrets; that started one Render deploy, so no second deployment trigger was issued. No reseeding, account cleanup, Production or paid-resource change occurred.

Public post-deployment health/database/PostGIS, discovery/detail, the new public Sai contract and invalid voice-upload validation passed. Live verification run `38838575751` is intentionally failed: the real AI search returned503 twice, matching startup diagnostic `provider_http_503`. The capabilities endpoint describes configuration availability; it does not prove current provider success. Gemini client/model/key configuration was not changed by Wave5. Manual browsing/search/filtering remains available; do not claim the AI-provider or handset gate has passed. Seven synthetic UI previews passed visual inspection, but handset/motion acceptance and comparison with the four unavailable full MP4s remain open. PR73 remains separate historical Wave4 documentation.

Read `WAVE5_BASELINE_1049_AR.md` for listing input7, inline rental requirements, native immutable fixed-fee Sai and lightweight Home/Account entries to the existing search session. Manual-stop whole-recording voice and retired viewings remain. Documentation-only Wave5 follow-ups preserved both application subtrees; the newer1058 state above supersedes that installer.

## Retained Wave4 baseline history

The attached October15 handoff explicitly rejects1043 as this wave's base. Work starts at `998f3456d5dd74b493052376cf0091737c1eaf21` (tree `5a256de722eae6819f45d269768964163afcd7e9`) on `work/wave4-baseline-1039`; all locally present baseline blobs were hash-verified before changes. Existing startup retry/cache changes are excluded. Read `WAVE4_BASELINE_1039_AR.md` for the listing version6, optional rental conditions, deferred post-publication Sai consent, whole-recording voice and retirement of the active viewing journey.

Wave4 implementation, CI49, APK1049 and the Frankfurt deployment completed at source `db378214ade105a7046a2d1069095070ac76f7a4`; handset acceptance and full-video comparison remain open. Two named reference MP4s were not attached; seven embedded reference images were reviewed, without a claim that either full video was watched. Handset/motion acceptance remains separate. Historical statements below refer to earlier work and do not override this explicit Wave4 scope.

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
