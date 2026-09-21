# Phase 1 — UX/UI Product Foundation

Status: COMPLETE — source and automated acceptance closed; real-device review deferred to Beta/launch readiness
Branch: `phase1/ux-product-foundation`
Issue: #6

## Product direction

The launch-critical product is a marketplace-first real-estate experience.

Primary journey:

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / matching are deferred and are not launch-critical. They are not exposed as active services/capabilities in the Phase 1 closure state unless the product owner explicitly re-approves them later.

Phase 0 remains closed.

## Phase 1 accepted outcome

Phase 1 provides:
- an Arabic RTL-first Material 3 design system with bundled Noto Sans Arabic assets and reusable marketplace components;
- public discovery without login;
- accepted role-aware navigation hierarchy;
- services below Account rather than a consumer bottom tab;
- professional listing controls progressively disclosed to verified publishing profiles;
- standardized property UI primitives and property-details conversion surface;
- existing map/list, search, filter, sort, empty/error/loading, conversation, and viewing behavior preserved;
- a cleaned services hub that distinguishes working paths from approved future directions without fake active navigation;
- deferred Property Requests / Researcher Requests / matching removed from the active services API contract;
- Phase 1 closure CI covering Laravel regression tests plus Flutter analysis, tests, UAT endpoint verification, and release APK build.

Real-device RTL/layout/keyboard/map/text-scale inspection remains required before public launch, but it is a Beta/launch-readiness gate rather than a reason to keep Phase 1 open.

## Accepted role navigation

### Anonymous
- العقارات
- حسابي

### Regular user
- العقارات
- الرسائل
- المعاينات
- حسابي

### Verified advertiser
- العقارات
- إعلاناتي
- الرسائل
- المعاينات
- حسابي

### Support agent
- لوحة الدعم
- الوارد
- مهامي
- الرسائل
- حسابي

### Support manager
- لوحة الدعم
- الأعمال
- الفريق
- حسابي

### Platform administration
- لوحة الإدارة
- المراجعات
- المستخدمون
- المنصة
- حسابي

Services and tools are reached from Account. Favorites are not a launch top-level destination. Publishing complexity is shown progressively to verified publishing profiles.

## Current routed product surfaces

- `/` role-aware shell
- `/auth`
- `/verify-phone`
- `/complete-profile`
- `/forgot-password`
- `/profile`
- `/account-verification`
- `/properties/:id`
- `/messages`
- `/messages/:id`
- `/notifications`
- `/bookings`
- `/services`
- `/support?case=:id`
- `/add-property`
- `/my-listings`

Additional operational routes remain available for authorized support/platform roles without being exposed to ordinary users.

## UX principles

### Marketplace-first
For the regular user, discovery of properties is the dominant experience. Published-property browsing remains public without login.

### Property-centered actions
Contact, conversation, viewing, share, save, and later agreement actions originate from a real property context when applicable.

### Progressive professional complexity
A normal user does not see professional listing-management complexity until context and verified publishing eligibility require it.

### RTL-first Arabic layout
Every redesigned surface is authored for Arabic RTL first, including alignment, hierarchy, icon direction, overflow, navigation labels, dialogs/sheets, keyboard/forms, text scaling, and small Android screens.

### Reusable system, not screen-by-screen styling
Visual changes reuse shared tokens/components instead of hard-coded one-off styling.

Implemented reusable foundation includes semantic colors, typography, spacing, surfaces, app bars, buttons, fields, chips, list rows, property cards/media/price/facts, section headers, status badges, inline messages, loading/skeleton/empty/error/unavailable states, navigation, bottom sheets, and dialogs.

## Phase 1 task closure

- W1 — historical rendered baseline is not required for closure; real-device review moved to Beta/launch-readiness acceptance.
- W2 — information architecture accepted and implemented.
- W3 — design system foundation implemented with typography, shared components, and tests.
- W4 — regular shell redesigned with public browsing preserved.
- W5 — property discovery/home retained and aligned to the accepted shell/design foundation.
- W6 — standardized reusable property-card primitives implemented.
- W7 — search/filter semantics retained within discovery.
- W8 — map/list switching, sorting, markers, area selection, and states retained.
- W9 — property details redesigned around gallery, price/location/facts, advertiser trust, sharing, property-linked messaging, viewing, contact, similar listings, and unavailable/error states.
- Closure cleanup — services surface/API contract aligned with marketplace direction and deferred request/matching concepts removed from active launch-facing capabilities.

## Phase 1 non-goals retained

Phase 1 did not implement:
- Property Requests / Researcher matching;
- rental contracts;
- payment activation;
- price indicators/valuation engine;
- Production infrastructure;
- broad new feature work.

## Handoff to Phase 2

The next implementation phase is **Phase 2 — Listing Journey Hardening**.

Phase 2 starts from the existing listing workflow and focuses on UX/state hardening, clear Draft/Preview/Submit behavior, full lifecycle regression coverage, and stronger likely-duplicate review support. It must not rebuild the working listing backend from scratch.
