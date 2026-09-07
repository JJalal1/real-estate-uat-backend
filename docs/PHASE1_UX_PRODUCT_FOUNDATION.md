# Phase 1 — UX/UI Product Foundation

Status: IMPLEMENTED — automated acceptance passed; final visual/device acceptance pending product-owner APK review
Branch: `phase1/ux-product-foundation`
Issue: #6

## Product direction

The launch-critical product is a marketplace-first real-estate experience.

Primary journey:

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / matching are not the launch-critical core journey. They are deferred unless the product owner explicitly re-approves them later.

Phase 0 is considered closed by product-owner decision. Phase 1 does not reopen Phase 0 unless a severe regression is discovered while redesigning current product surfaces.

## Phase 1 implemented outcome

The Phase 1 code foundation now provides:
- an Arabic RTL-first Material 3 design system with bundled Noto Sans Arabic assets and reusable marketplace components;
- public discovery without login;
- the accepted role-aware navigation hierarchy;
- services moved below Account rather than a consumer bottom tab;
- professional listing controls progressively disclosed to verified publishing profiles;
- a standardized property card and property-details conversion surface;
- existing map/list, search, filter, sort, empty/error/loading, conversation, and viewing behavior preserved;
- automated Flutter analysis, tests, UAT compile-time endpoint verification, and release APK build in CI.

The remaining Phase 1 acceptance gate is visual/device review of the generated UAT APK. Automated checks do not substitute for real-device checks of RTL layout, text scale, keyboard, overflow, map rendering, and subjective visual quality.

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
Every redesigned surface must be evaluated in Arabic RTL first, including alignment, text hierarchy, icon direction, overflow, navigation labels, dialogs/sheets, keyboard/forms, text scaling, and small Android screens.

### Reusable system, not screen-by-screen styling
Visual changes reuse shared tokens/components instead of hard-coded one-off styling.

Implemented reusable foundation includes semantic colors, typography, spacing, surfaces, app bars, buttons, fields, chips, list rows, property cards/media/price/facts, section headers, status badges, inline messages, loading/skeleton/empty/error/unavailable states, navigation, bottom sheets, and dialogs.

## Phase 1 task status

- W1 — baseline evidence: superseded by direct implementation plus final owner device review; no historical baseline is required to ship the current Phase 1 candidate.
- W2 — information architecture: accepted and implemented in `docs/PHASE1_ACCEPTED_IA.md` and the role-aware shell.
- W3 — design system foundation: implemented, including typography activation, shared components, and widget/theme tests.
- W4 — regular shell redesign: implemented with public browsing preserved.
- W5 — property discovery/home: existing map/list marketplace discovery retained and aligned to the accepted shell/design foundation.
- W6 — property card: standardized reusable property-card primitives implemented.
- W7 — search/filter interaction: existing search/filter semantics retained within the discovery flow.
- W8 — map/list discovery: existing map/list switching, sorting, markers, area selection, and states retained.
- W9 — property details: redesigned around gallery, price/location/facts, advertiser trust, sharing, property-linked messaging, viewing, contact, similar listings, and unavailable/error states.

Automated acceptance for these implementation tasks is complete when the Phase 1 Flutter CI run is green and produces the UAT APK. Visual acceptance remains the product owner's device check.

## Acceptance ownership

Ordinary ChatGPT session owns roadmap, backend/API/database/security review, GitHub/CI review, UAT verification, documentation, and technical acceptance.

Rendered-device visual acceptance belongs to the product owner for this candidate APK. Work/Astra remains optional for later visual polish and regression work; it is not required to complete this automated Phase 1 build.

## Phase 1 non-goals

Do not implement in this phase unless explicitly pulled forward:
- Property Requests / Researcher matching;
- rental contracts;
- payment activation;
- price indicators/valuation engine;
- Production infrastructure;
- broad new feature work.
