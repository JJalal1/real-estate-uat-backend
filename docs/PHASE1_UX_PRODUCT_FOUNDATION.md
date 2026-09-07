# Phase 1 — UX/UI Product Foundation

Status: ACTIVE
Branch: `phase1/ux-product-foundation`
Issue: #6

## Product direction

The launch-critical product is a marketplace-first real-estate experience.

Primary journey:

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / matching are not the launch-critical core journey. They are deferred unless the product owner explicitly re-approves them later.

Phase 0 is considered closed by product-owner decision. Phase 1 does not reopen Phase 0 unless a severe regression is discovered while redesigning current product surfaces.

## Phase 1 goals

1. Capture the current rendered application baseline before visual changes.
2. Simplify the information architecture and role-aware navigation.
3. Establish one RTL-first design system and component language.
4. Redesign current product surfaces incrementally, one small scope at a time.
5. Preserve backend authorization, privacy, listing-review, duplicate-property, and support rules.
6. Leave the application visually coherent and ready for the later launch-critical journey phases.

## Current product surface inventory

### Public / regular user

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

Regular shell currently exposes:
- حسابي
- الإعلانات
- الحجوزات
- المحادثات
- الخدمات

This navigation is functional but does not match the desired marketplace-first hierarchy. Phase 1 should propose a simpler consumer hierarchy centered on discovery and property actions rather than treating account/services as peers of discovery.

### Support agent

Current shell:
- الرئيسية
- مهامي
- مركز الدعم
- الرسائل
- حسابي

### Support manager

Current shell:
- لوحة الدعم
- الأعمال
- الفريق
- البلاغات
- حسابي

### Platform administration

Current shell:
- لوحة الإدارة
- المراجعات
- المستخدمون
- المنصة
- حسابي

### Additional routed operational screens

- `/admin/access`
- `/admin/dashboard`
- `/admin/settings`
- `/admin/audit-log`
- `/admin/listing-review`
- `/broker/account-verification`
- `/admin/broker-account-verifications`
- `/admin/account-verifications`
- `/admin/regions`
- `/admin/message-reports`
- `/admin/support`
- `/support/workspace`
- `/support/users`
- `/support/worklog`

## UX principles for this phase

### Marketplace-first

For the regular user, discovery of properties must be the dominant experience. Public browsing must remain available without login.

### Property-centered actions

Contact, conversation, viewing, share, save, and later agreement actions should originate from a real property context when applicable.

### Progressive professional complexity

A normal user should not see professional verification, listing management, office/broker tooling, or support/admin complexity until context requires it.

### RTL-first Arabic layout

Every redesigned surface must be evaluated in Arabic RTL first, including:
- alignment;
- text hierarchy;
- icon direction;
- overflow;
- bottom navigation labels;
- dialogs/sheets;
- keyboard and form layout;
- small Android screens.

### Reusable system, not screen-by-screen styling

Visual changes should reuse shared tokens/components rather than hard-coded one-off styling.

Target reusable foundation:
- semantic colors;
- typography scale;
- 4/8-based spacing scale;
- page gutters;
- surface/card styles;
- app bars;
- buttons;
- inputs;
- chips/filters;
- list items;
- property cards;
- section headers;
- skeleton/loading states;
- empty/error/retry states;
- status badges;
- bottom sheets/dialogs;
- role-aware navigation components.

## Work / Astra execution contract

Work must operate in small tasks. Do not combine tasks unless explicitly authorized.

For every Work task:
1. Read `AGENTS.md` and this file first.
2. Re-check current Git HEAD before editing.
3. Preserve existing business/security behavior.
4. Do only the stated task.
5. Do not redesign unrelated screens.
6. Use Computer Use when the task asks for rendered-app evidence.
7. Return:
   - commit SHA;
   - files changed;
   - tests run and result;
   - before/after screenshots when visual;
   - any blocker or product decision discovered.
8. Stop after delivery. Do not start the next task automatically.

## Phase 1 task queue

### W1 — Visual baseline capture

Purpose: document the current product before redesign.

Scope:
- no code changes;
- launch the current UAT APK/emulator;
- capture screenshots for regular public/anonymous state and the main role shells;
- record visible layout/navigation/consistency defects;
- focus on evidence, not redesign proposals.

Required baseline captures:
- regular shell / property discovery;
- property details;
- account;
- services;
- messages;
- bookings;
- add-property entry if eligible;
- support agent shell;
- support manager shell;
- platform admin shell.

Deliverable: screenshot set + concise defect inventory only.

### W2 — Information architecture proposal

Purpose: propose navigation structure before coding.

Scope:
- no code changes;
- use W1 evidence plus current route inventory;
- propose regular-user shell hierarchy;
- propose professional-account entry points;
- preserve separate support/manager/platform operational shells unless evidence supports a small simplification;
- identify screens that should move under account/overflow rather than top-level tabs.

Deliverable: one recommended IA, one alternative only if materially different, and a migration map from current destinations.

### W3 — Design system foundation

Purpose: create reusable visual primitives before redesigning many screens.

Scope:
- Flutter theme/tokens/shared components only;
- no broad screen redesign;
- preserve behavior/routes/API;
- add or refine typography, spacing, surfaces, buttons, fields, chips, status/empty/error/loading primitives as required;
- include tests or golden/widget checks where practical.

Deliverable: commit + screenshots of component showcase or representative existing screen proving the foundation.

### W4 — Regular shell redesign

Purpose: implement the accepted regular-user navigation architecture.

Scope:
- regular shell only;
- no support/manager/platform redesign;
- no backend/API changes unless a blocking defect is found and reported first;
- preserve anonymous public browsing.

Deliverable: commit + screenshots + navigation test evidence.

### W5 — Property discovery/home redesign

Purpose: redesign the main marketplace surface after W4 acceptance.

Scope:
- one discovery/home surface only;
- no property-details redesign yet;
- reuse the accepted design system.

### W6 — Property card redesign

Purpose: standardize the core property preview component.

Scope:
- card/list preview component only;
- cover long Arabic title, price, location, key facts, unavailable state if already supported.

### W7 — Search/filter interaction redesign

Purpose: make discovery controls coherent and compact.

Scope:
- search/filter UI only;
- preserve backend filter semantics.

### W8 — Map/list discovery polish

Purpose: improve map/list switching and map result affordances.

### W9 — Property details redesign

Purpose: make the property page the primary conversion surface.

Scope includes:
- gallery;
- title/price/location;
- property facts;
- advertiser identity/trust summary;
- contextual save/share/contact/viewing actions when available;
- clear unavailable/error state.

## Acceptance ownership

Ordinary ChatGPT session owns:
- roadmap and task decomposition;
- backend/API/database/security review;
- GitHub/CI review;
- UAT/Render/Supabase verification;
- documentation;
- acceptance or rejection of each Work task.

Work/Astra owns:
- rendered-device observation;
- UX/visual proposal execution;
- Flutter visual implementation;
- visual regression evidence.

The product owner is asked only for meaningful product choices or final acceptance where alternatives are subjective.

## Phase 1 non-goals

Do not implement in this phase unless explicitly pulled forward:
- Property Requests / Researcher matching;
- rental contracts;
- payment activation;
- price indicators/valuation engine;
- Production infrastructure;
- broad new feature work.
