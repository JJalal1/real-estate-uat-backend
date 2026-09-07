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

`AGENTS.md` and `docs/AI_*.md`/architecture/business/security/runbook docs are the persistent engineering handoff for future ChatGPT/Codex sessions. They must be updated when accepted product rules or architecture change.

## D-019 — Phase 0 is closed by product-owner decision

As of 2026-09-07, Phase 0 is considered closed. Rendered-device inspection continues in Phase 1 as UX baseline evidence, not as a blocker that reopens Phase 0 unless a severe regression is discovered.

## D-020 — Marketplace-first launch journey

The launch-critical journey is:

`verified advertiser -> create property -> support review -> publish -> public discovery -> property details -> contact/conversation -> viewing -> agreement`

Property Requests / Researcher Requests / broker-driven matching are deferred and are not launch prerequisites unless explicitly re-approved later.

## D-021 — Phase 1 work is split between ordinary ChatGPT and Work/Astra

Ordinary ChatGPT owns roadmap, backend/API/database/security/CI review, UAT verification, docs, and acceptance. Work/Astra primarily owns rendered-device observation, UX/UI proposals, Flutter visual implementation, and visual-regression evidence. Work tasks must remain small, scoped, and independently reviewable.
