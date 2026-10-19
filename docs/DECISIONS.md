# Decisions — REAL ESTATE

## D-LISTING-FLOW — October19 observed1090 handset correction

The owner explicitly requests easy, fast listing steps, a visible manual map requirement, no redundant Sai-kind display and no repeated location request after returning. Preserve the purchased template creation menu from verified1092. Keep the canonical editor and backend workflow; fix point invalidation for mere text/spelling changes, bound the optional reverse lookup and retain explicit point confirmation. Only a real governorate change or explicit point replacement changes location state. A selected numeric Sai fact carries its discriminator internally, never as another selectable card. Review and submission remain explicit; `LISTING_FLOW_1092_AR.md` defines automated and handset acceptance.


## D-LISTING-DESIGN — October19 current1087 reference wave

The owner explicitly authorizes new colors, rounded components, consolidated professional navigation and a centered animated creation menu. Preserve existing entities, real auth and protected workflows. Supplement sparse model extraction with conservative explicit facts from the complete Arabic brief, never guessed missing data. Apply reviewed proposals together to the canonical editor; offer the existing complete-clip route alongside live dictation with manual finish. Move comparison beside favorites on listing photos and localize price display without changing values. `LISTING_DESIGN_WAVE_AR.md` defines scope and acceptance limits; physical-device microphone acceptance remains separate from CI previews.

This file records product/engineering decisions that AI agents must not silently reverse.

## D-VOICE-REF — October16 explicit voice reference

Match the supplied in-composer live dictation and explicit send interaction on current1058. Partial hypotheses are display-only, finalized segments accumulate until manual finish, and cancel/error restores typed context. Finished text remains editable before search or reviewed listing preparation. Retain structured Home/search/listing sections and whole-clip fallback without new keys, runtime dependencies, backend writes, auto-send or publication. This latest request supersedes the earlier batch-only presentation, not the manual-stop/no-partial-execution boundary. See `VOICE_REFERENCE_20261016_AR.md`.

Accepted source `2822ab45be21a6a715f0b0bafafce24fe449ff9f` passed all five CI63 gates and original APK1063 was verified/delivered. PR78 merged as `807d34330d1d9c4687308d54f55618b29ad2f28e`, with the complete tested tree retained. Backend is unchanged; no Render deployment. Actual handset recognition acceptance remains open. See `VOICE_REFERENCE_1063_DELIVERY_AR.md`.

## D-AI-DRAFT — October16 broker publishing assistance

Owner delegation authorizes a focused draft-preparation helper on1052. Reuse the current listing editor, voice recording, authorization and support review. Fact-bound server composition and review prevent deselected proposals from leaking into copy. A single transient-provider retry shares the original deadline and charges the persistent UTC budget on every attempt. Labeled literal-text organization keeps this new entry useful during provider failure without claiming AI success. No new schema, providers, keys, automatic publication or sending.

The owner explicitly approved PR76 merge and the existing-UAT deployment on October16 at15:42 Asia/Aden. APK1058/CI58 and the merged tree match exactly. Live health/auth boundaries passed; real AI search failed once near25s then passed in12.8s, so availability remains a measured variable rather than a guarantee. See `BROKER_AI_1058_DEPLOYMENT_AR.md`.

## D-W5 — October16 current1049 and focused refinement

The owner selected current1049 over the1039 label in the new handoff. Work starts at `db378214ade105a7046a2d1069095070ac76f7a4` and retains Wave4. `WAVE5_BASELINE_1049_AR.md` defines listing input7, optional rental unit position with support identity review, inline rental chips, immutable native fixed Sai with unchanged owner/fallback/split policies, and lightweight Home/Account entries to existing smart search. No Production, paid resource, cleanup, active viewing journey or1043 startup import is authorized.

## D-001 — UAT first, no Production yet

Current work targets UAT/staging. Production infrastructure, Production database, Play Store release, real payment data, and real customer identity data are out of scope until explicitly approved.

## D-002 — Git HEAD is the current source of truth

Current repository state outranks old handoff snapshots and ZIP names. Historical Result ZIPs are evidence for what happened, not automatically the current source.

## D-003 — Backend authorization is authoritative

Flutter visibility/disabled controls are UX only. Laravel must enforce sensitive permissions and resource ownership.

## D-004 — No broker hierarchy or regional exclusivity

Do not add master/sub-brokers, territory ownership, regional exclusivity, or a head-broker system.

## D-005 — Support uses shared queue -> claim

Eligible support staff see unassigned work. The first valid claim wins; backend must protect concurrency. Managers may reassign/escalate according to permissions.

## D-006 — Published properties are public

Published/approved properties must be browsable without requiring login.

## D-007 — UAT test OTP is staging-only

Allowlisted UAT test OTP can exist in staging. Production must not allow it.

## D-008 — Sensitive storage stays private

Do not make the private Supabase bucket public to simplify testing. Identity/selfie/ownership/private documents require controlled access.

## D-009 — Product services are free

The active product journey has no paid promotion, paid listing highlighting, paid account highlighting, paid upgrades, or paid service packages. Legacy payment structures may stay dormant when removal is risky/unnecessary.

## D-010 — One services UI, backend-driven capabilities

Owner, broker, and office share one services design. Backend capabilities decide which professional actions are available.

## D-011 — Viewing starts from a property

No generic top-level viewing service. Viewing is contextual to a specific property and should connect to notification/conversation/booking flows.

## D-012 — Reuse existing workflows/entities

When adding Favorites, Contracts, or new integrations, first inspect and reuse current property, notification, conversation, viewing/booking, role, and audit infrastructure. Do not create parallel systems without a demonstrated need.

## D-013 — Price indicators and valuation share one backend engine

When implemented, both use eligible published/approved listing data and must return insufficient-data rather than fabricate a price.

## D-014 — Legal library is informational

Do not call templates government-certified, officially notarized, or legal advice without a real verified integration/source supporting that claim.

## D-015 — Branch + PR + CI for AI feature work

AI development should use a focused branch and Pull Request. Do not directly push feature work to `main`. CI is an independent quality gate and product-owner approval remains required for merge.

## D-016 — Do not disable accepted-source guards to make CI green

If a guarded file changes intentionally, prove the new state, then update only the relevant accepted hash. Do not remove or weaken the guard as a shortcut.

## D-017 — Measure performance before optimization

Distinguish Render cold start, cross-region DB latency, API/SQL behavior, and Flutter UI performance. Do not add caching or rewrite code without evidence.

## D-018 — AI documentation lives with the code

`AGENTS.md` and `docs/AI_*.md`/architecture/business/security/runbook docs are the persistent engineering handoff for future ChatGPT sessions. They must be updated when accepted product rules or architecture change.

## D-019 — Phase 0 is closed by product-owner decision

Phase 0 is considered closed. Later visual inspection does not reopen it unless a severe regression is discovered.

## D-020 — Marketplace-first launch journey

The launch-critical journey is:

`verified advertiser -> create property -> support review -> publish -> public discovery -> property details -> contact/conversation -> viewing -> agreement`

Property Requests / Researcher Requests / broker-driven matching are deferred and are not launch prerequisites unless explicitly re-approved later.

## D-021 — Available engineering tools must not freeze product progress

Repository/cloud engineering, Flutter source changes, backend work, tests, CI, and documentation may continue through the available ChatGPT tools. Real-device subjective visual review is valuable but belongs to Beta/launch-readiness acceptance when device/emulator access exists.

## D-022 — Phase 1 is closed; Phase 2 is Listing Journey Hardening

Phase 1 UX/UI Product Foundation is closed at source/automated-acceptance level. The next implementation phase is Phase 2 — Listing Journey Hardening. Phase 2 must reuse the existing listing workflow and focus on state/UX/regression/duplicate-detection hardening rather than rebuilding listings from scratch.

## D-023 — Deferred request/matching concepts are not active service capabilities

Property Requests, Researcher Requests, and broker-driven request matching are deferred product concepts. They must not appear as active launch-facing service actions or server capabilities until the product owner explicitly re-approves them and their persistence/API/UI/tests are implemented.

## D-024 — Saving a listing and submitting it for review are separate actions

The listing editor must never treat completing the form as implicit submission. The canonical advertiser controls are:

`Save Draft -> Preview -> explicit Submit for Review`

Preview is non-mutating. Create/update operations save the listing without entering review unless the user explicitly confirms submission. If submission fails after a successful save, the saved draft remains recoverable.

## D-025 — Returned-for-correction context survives editing

`returned_for_correction` is an editable workflow state, not a disposable display label. The support reason must remain visible while the advertiser edits the same listing. Only explicit resubmission clears the correction reason and moves the listing back to `submitted`.

Do not create a replacement listing merely to satisfy a correction request.

## D-026 — Exact duplicate blocking and likely-duplicate review are different controls

Exact physical-property identity through `PropertyAsset` remains the hard server-side publication boundary. A listing must not publish while the same physical asset is already published.

Likely-duplicate detection is advisory and explainable. Current signals include geographic proximity, normalized-address similarity, area similarity, and matching bedroom/bathroom facts. A likely match must be shown to support for human investigation rather than silently merged or fuzzy-rejected.

When likely-duplicate candidates exist, approval requires an auditable human reason explaining why the candidates are not the same property, or the reviewer must link the listing to the correct existing `PropertyAsset`. Approval still performs the exact duplicate check inside the server transaction.

## D-027 — Property-specific owner evidence belongs to the canonical listing editor

For an approved owner profile, the listing editor collects the relationship evidence for that specific property: document type, document owner name, relationship type/note where applicable, and the private ownership/relationship document. Do not expose a generic proof-upload shortcut that bypasses this structured relationship context.

Verified brokers and offices must not be forced to upload unrelated ownership evidence merely to publish under their approved professional profile.

## D-028 — Phase 2 is closed; Phase 3 is Buyer Discovery Completion

Phase 2 Listing Journey Hardening is closed at source/automated-acceptance level after a successful gate that covers full Laravel regression, PostgreSQL 17 + PostGIS migration/security/listing lifecycle acceptance, Flutter analysis/tests, UAT endpoint verification, and release APK build/upload.

The next implementation phase is Phase 3 — Buyer Discovery Completion. It must reuse the existing discovery implementation, harden list/map/details/search/filter/sort/public-boundary behavior, and add server/account-bound Favorites. Phase 3 must not silently expand into deferred request/matching, payments, contracts, valuation, or Production work.

## D-029 — Phase 3 is closed; Phase 4 hardens the single conversation/viewing system

Phase 3 Buyer Discovery Completion + Server-side Favorites is closed by product-owner acceptance. Phase 4 must reuse the existing property-linked conversation, notification, viewing-booking, audit, and authorization infrastructure. It must not create a second chat system or a parallel booking state machine.

Phase 4 scope is messaging reliability/privacy/read state, conversation history, viewing transitions/concurrency, exact notification/deep-link destinations, Flutter UX hardening, and Laravel/PostgreSQL/Flutter/APK regression.

## D-030 — Reschedule acceptance and message retries are explicit two-party/server contracts

A replacement viewing time is a proposal, not an implicit confirmation. If the advertiser changes the appointment, the requester must explicitly accept the new time. If the requester changes it, the advertiser confirms it. The party proposing a replacement time cannot unilaterally turn its own proposal into a confirmed appointment.

Private message retries use a client-supplied logical message key. Retrying the same key with the same body is idempotent; reusing the same key for different content is a conflict. Long conversation history is paged from newest to older rather than truncating the newest messages.

## D-031 — Phase 4 is accepted; later roadmap items are deferred, not automatically next

Phase 4 Messaging + Viewing Journey Hardening is closed by explicit product-owner real-device acceptance after successful CI, Supabase UAT verification, and Render UAT deployment.

The previously discussed follow-on sequence — in-app agreement/rental contracts, price indicators/valuation, Real-estate Guide/legal documents, and Production/launch readiness — is preserved as future backlog only. It must not be treated as the active next phase or started automatically.

The product owner explicitly chose to complete other product priorities first. The next work package must therefore be defined from those newer priorities. Old phase numbering does not override a newer explicit product-owner decision.

No Phase 4 acceptance authorizes a merge to `main` or any Production deployment.

## D-032 — October 13 marketplace and dynamic listing refinement

The owner authorizes thoughtful refinement using eBroker assets and the supplied Houzi references, rather than literal template copying. Verified advertisers start in the marketplace with a separate work area. Listing input v4 distinguishes whole floors/buildings and moves photos and Sai into their appropriate form contexts. New Sai terms are customer-paid, with unchanged percentage policies and immutable historical terms. The first assisted-search path proposes editable filters and fetches real canonical API results; no external AI provider is enabled. UAT checks and handset/reference-video acceptance remain separate gates. See `UX_REFINEMENT_ROUND2_AR.md`.

## D-W3 — Contextual unit scope and reviewed professional activation

The October 13 Wave3 handoff supersedes standalone whole-floor selection and owner professional tabs. Preserve exact old whole-floor identity, offer one personal property under existing verification, and require approved broker/office identity for CRM/workspace. The backend enforces the cap independently of Flutter; pending upgrades do not grant professional tools.

## D-W3-UAT — One-shot fixture replacement, operational preservation

The owner authorized replacing old UAT marketplace fixtures only. Match exact legacy email/phone pairs, exclude any operational role/direct privilege/platform owner, back up sanitized scoped rows privately, and verify protected account snapshots. No global truncate, FK disabling or RLS change. Only scoped immutable DELETE guards are removed/recreated within the enclosing transaction; ordinary UPDATE/history guards stay active. An unforeseen financial/contract history stops cleanup. No reset endpoint or repeated cleanup on deploy.


## D-W4 — Explicit1039 base and focused product corrections

The October15 handoff mandates source998f3456 as base and excludes1043's home startup/cache changes. It supersedes active viewing-journey requirements: no booking UI/API or viewing notifications, no alternative calendar; retain historical records and normal participant-only messages. Broker management moves into a secondary sheet.

New listing input6 stores optional selected rental conditions and defers platform consent to the existing post-publication Sai attestation. No financial version is edited or automatically accepted; pending custom terms must be explicitly attested before settlement. Existing rates, payer, monthly basis and accepted historical snapshots are unchanged. Public price+rate presentation is automatic. Whole-floor selection is removed while legacy identity stays read-only.

Recording is foreground-only and manually stopped; full-clip transcription uses Laravel's existing Gemini guard, never a Google recognition Activity or silence endpointing. No partial or provider-truncated transcript may execute. The full-reference-video and handset gates remain outstanding until the two source videos are supplied and actual motion is reviewed.
