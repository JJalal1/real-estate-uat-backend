# Phase 2 — Listing Journey Hardening

Status: IN PROGRESS
Branch: `phase2/listing-journey-hardening`
Issue: #8
Base: Phase 1 closure candidate `a624d5bb6e006b6835e25b2ed1dd6893e08d9a70`

## Goal

Harden the existing listing workflow end to end without replacing the current Laravel/property/support architecture.

Authoritative acceptance journey:

`verified advertiser -> create -> save draft -> media -> location -> property-specific evidence -> preview -> explicit submit -> shared support queue -> atomic claim -> return for correction -> edit same listing -> resubmit -> review -> approve -> publish -> public discovery`

## Existing foundation being reused

- Laravel draft create/update and explicit submit endpoint.
- `ListingWorkflowService` state transitions.
- `PropertyAsset` exact physical-property identity and duplicate-publication check.
- shared support review queue and atomic listing claim.
- private listing proof documents and audited access.
- public property browse/search/map/details.
- Flutter My Listings, listing editor, property details, notifications and support review surfaces.

## Phase 2 work packages

### P2.1 Lifecycle and UX contract
- explicit Save Draft / Preview / Submit actions;
- preview must not mutate backend review state;
- editing a returned listing keeps the correction context until resubmission;
- My Listings exposes only state-valid actions.

### P2.2 Media, location and evidence hardening
- one to twelve public listing images before submission;
- location coordinates plus readable address;
- owner property-specific ownership/relationship evidence;
- broker/office accounts do not receive unrelated ownership requirements;
- private evidence never becomes public listing media.

### P2.3 Support correction and review hardening
- first valid claim wins;
- support worker must own the claimed review before sensitive decisions;
- return reason stays visible to the advertiser;
- same listing is edited and resubmitted;
- approval/rejection remains audited.

### P2.4 Likely duplicate review
- preserve exact `PropertyAsset` publication blocking;
- compute explainable likely-duplicate signals from geographic proximity, normalized address and property facts;
- uncertain similarity is a human-review signal, not an automatic rejection;
- support may explicitly clear a suspicion with a reason or link the listing to an existing physical asset;
- approval re-checks duplicate state.

### P2.5 Notifications and public transition
- advertiser receives correction, approval and rejection notifications linked to the real property;
- unpublished listings stay out of public discovery;
- approved listings become publicly readable/searchable.

### P2.6 Regression and CI
- Laravel lifecycle, authorization, duplicate and notification tests;
- Flutter repository/UI/source-contract tests;
- release UAT APK build;
- no Production deployment or merge without product-owner approval.

## Non-goals

- Property Requests / Researcher Requests / matching;
- Favorites;
- Rental Contracts;
- Price Indicators / Property Valuation;
- payments;
- Production infrastructure.

## Acceptance gate

Phase 2 is closed only when CI proves the full lifecycle and the UAT candidate can be built. Real-device subjective visual acceptance remains a Beta/launch-readiness gate.
