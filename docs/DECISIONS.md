# Decisions — REAL ESTATE

This file records product/engineering decisions that AI agents must not silently reverse.

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
