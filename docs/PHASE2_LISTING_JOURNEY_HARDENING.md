# Phase 2 — Listing Journey Hardening

Status: CLOSED — source/automated acceptance
Branch: `phase2/listing-journey-hardening`
Issue: #8
PR: #9 (open, unmerged; product-owner approval required before merge)
Base: Phase 1 closure candidate `a624d5bb6e006b6835e25b2ed1dd6893e08d9a70`
Final automated-gate head: `a8226f9ac5c8375828c34451150f2736960d0725`

## Goal

Harden the existing listing workflow end to end without replacing the current Laravel/property/support architecture.

Authoritative accepted journey:

`verified advertiser -> create -> save draft -> media -> location -> property-specific evidence -> preview -> explicit submit -> shared support queue -> atomic claim -> return for correction -> edit same listing -> resubmit -> review -> approve -> publish -> public discovery`

## Accepted implementation

### P2.1 Lifecycle and UX contract
- Save Draft / Preview / Submit for Review are explicit separate actions.
- Preview does not mutate backend review state.
- Create/update saves without implicit submission.
- A failed submit after a successful save leaves a recoverable saved listing.
- Editing `returned_for_correction` keeps the correction state/reason until explicit resubmission.
- My Listings exposes state-valid edit, correction, submit/resubmit, view and delete actions.

### P2.2 Media, location and evidence hardening
- submission requires listing media and server-side validation;
- the listing editor preserves location coordinates plus readable address;
- approved owners provide structured property-specific relationship evidence in the canonical editor;
- verified brokers/offices are not forced to provide unrelated ownership proof;
- private evidence remains separate from public listing media;
- the legacy generic My Listings proof shortcut was removed to avoid bypassing the structured owner-evidence contract.

### P2.3 Support correction and review hardening
- shared queue -> first valid atomic claim remains authoritative;
- sensitive review decisions require the valid claimant;
- review decision paths use stronger transaction/row-lock protection;
- correction reason remains visible while the advertiser edits the same listing;
- the same listing is resubmitted rather than replaced;
- approval/rejection/correction paths remain auditable.

### P2.4 Likely duplicate review
- exact `PropertyAsset` duplicate-publication blocking remains the hard server-side boundary;
- likely-duplicate candidates are calculated from explainable signals including geographic proximity, normalized-address similarity, area similarity and matching bedroom/bathroom facts;
- uncertain similarity is a human-review signal, not an automatic fuzzy rejection or silent merge;
- approval with candidates requires an auditable reviewer reason clearing the suspicion, or linking the listing to the correct existing physical asset;
- approval re-checks exact duplicate state inside the server transaction.

Image-similarity/fingerprint infrastructure was not added in Phase 2 because the accepted explainable property/location signals plus exact physical-asset blocking provide the required launch-safe control without introducing a new media-processing subsystem.

### P2.5 Notifications and public transition
- advertiser receives correction, approval and rejection notifications linked to the actual property;
- Flutter notification routing already supports property destinations;
- unpublished listings remain outside public discovery;
- approved listings become publicly readable/searchable according to the existing public property contract.

### P2.6 Regression and CI
Phase 2 has a dedicated CI gate covering:
- full Laravel regression suite;
- PostgreSQL 17 + PostGIS disposable-database migration chain;
- PostgreSQL schema/security regression suite;
- Phase 2 listing lifecycle acceptance on PostgreSQL/PostGIS;
- Flutter static analysis;
- full Flutter test suite;
- compile-time UAT endpoint verification;
- release UAT APK build and artifact upload.

## Final acceptance evidence

GitHub Actions run #42 (`34169314754`) completed successfully on head `a8226f9ac5c8375828c34451150f2736960d0725`.

All three jobs were green:
1. Laravel listing regression suite;
2. PostgreSQL 17 and PostGIS listing acceptance;
3. Flutter analysis tests and UAT APK.

The Flutter job successfully completed `Build UAT APK` and `Upload UAT APK`.

Artifact:
- `real-estate-phase2-uat-apk-42`
- generated from the Phase 2 branch/head above.

## Environment / release boundary

- No merge has been performed. PR #9 must not be merged without explicit product-owner approval.
- Production was not touched.
- The existing Render UAT service still tracks the older stabilization branch with auto-deploy disabled; Phase 2 has not been represented as live Render UAT without the approved integration/merge sequence.
- No new paid infrastructure was created.
- Real-device subjective visual acceptance remains a Beta/launch-readiness gate and does not reopen Phase 2 source/automated acceptance.

## Non-goals preserved

Phase 2 did not expand into:
- Property Requests / Researcher Requests / matching;
- Favorites;
- Rental Contracts;
- Price Indicators / Property Valuation;
- payments;
- Production infrastructure.

## Closure

Phase 2 is CLOSED at source/automated-acceptance level.

The next implementation phase is **Phase 3 — Buyer Discovery Completion**, including public discovery hardening and server/account-bound Favorites.
