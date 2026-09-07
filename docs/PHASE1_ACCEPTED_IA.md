# Phase 1 — Accepted Information Architecture

Status: ACCEPTED for implementation planning
Source: W2 source-based navigation review, product-owner marketplace direction, current Phase 1 rules
Branch: `phase1/ux-product-foundation`

## Context

W1 rendered-device capture remains deferred because the current Work environment did not expose callable Computer Use/emulator/ADB access. No visual evidence is claimed here.

W2 was reviewed against the current Flutter router, role-aware shell, Phase 1 direction, business rules, and workflows. The source-based information architecture is accepted as the implementation target, subject to later visual validation when Computer Use is available.

## Launch-critical product journey

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / matching are not launch-critical and must not drive primary navigation. They remain deferred unless the product owner explicitly re-approves them later.

## Accepted consumer navigation

### Anonymous visitor

Default landing: public property discovery.

Top-level destinations:
- العقارات
- حسابي

Published properties and property details remain browsable without login. Authentication should be requested only when an action actually requires an account, and the initiating property/action context should eventually be preserved through authentication.

### Regular authenticated user

Default landing: property discovery.

Top-level destinations, RTL logical order:
- العقارات
- الرسائل
- المعاينات
- حسابي

### Verified owner / broker / real-estate office

Default landing: property discovery.

Top-level destinations, RTL logical order:
- العقارات
- إعلاناتي
- الرسائل
- المعاينات
- حسابي

Professional type changes capability/content, not the overall marketplace shell. Backend authorization remains authoritative.

## Accepted operational navigation

### Support agent

Default landing: support overview.

Top-level destinations:
- لوحة الدعم
- الوارد
- مهامي
- الرسائل
- حسابي

The shared incoming queue and claimed My Tasks remain separate concepts. First valid claim wins and backend concurrency remains authoritative.

### Support manager

Default landing: support management overview.

Top-level destinations:
- لوحة الدعم
- الأعمال
- الفريق
- حسابي

Reports belong under Works as a filter/shortcut rather than a duplicate permanent tab.

### Platform owner

Default landing: platform overview.

Top-level destinations:
- لوحة الإدارة
- المراجعات
- المستخدمون
- المنصة
- حسابي

The platform owner remains an overseer, not a default daily support claimant.

## Accepted destination placement

- Public map/list/search/filter remains one top-level `العقارات` destination. Search and map/list are modes inside discovery, not separate products.
- `إعلاناتي` is a top-level advertiser destination for verified owner/broker/office profiles.
- `أضف عقار` is an action inside My Listings, with optional contextual shortcuts to the same canonical flow. It is not a permanent bottom tab.
- Messages remains one canonical inbox/conversation system. Do not create parallel chat experiences.
- Viewing follow-up is labeled `المعاينات`; creation of a viewing request always starts from a specific property.
- Account contains profile, authentication/recovery, professional verification, notifications, personal help/support, and secondary tools.
- Services moves under Account as `الخدمات والأدوات`; it is not a consumer bottom-navigation tab.
- Consumer support cases belong under Account -> `المساعدة والدعم`. This remains distinct from staff support workspaces.
- Favorites is not promoted to a top-level tab before the account-bound server implementation exists.
- Property Requests / Researcher Requests / matching receive no primary tab or launch-critical quick-card treatment.
- Contracts, price indicators, valuation, guide, and legal documents remain secondary/later service candidates until implemented.
- Operational users must eventually have a clear secondary `تصفح العقارات` entry to public discovery without replacing their operational default shell.

## Canonicalization principles

Do not duplicate:
- public discovery;
- property detail for the same property;
- inbox/conversation for the same thread;
- My Listings or create/edit listing workflows;
- booking/viewing collections merely to represent different entry labels;
- support task lists when filters can express scope/type/status;
- professional verification entry points except retained compatibility routes;
- governance/access destinations.

Older support/admin/broker-verification routes are compatibility surfaces until separately assessed. Do not delete them merely because the new shell does not expose them.

## Later navigation fixes to preserve context

These are accepted needs but are not part of the design-system task:
- preserve property/action return context through authentication;
- preserve booking/task/listing entity identifiers through notifications and dashboard shortcuts;
- give primary shell destinations stable route identities while preserving compatible existing URLs;
- standardize Arabic labels such as `الرسائل` and `المعاينات`;
- distinguish consumer help from staff support work clearly;
- remove misleading labels such as platform `الخدمات والمدفوعات` when the destination is the free services hub.

## Constraints that remain unchanged

- Backend authorization is authoritative.
- Published properties remain public.
- No broker hierarchy or regional exclusivity.
- Shared queue -> claim remains the support model.
- Sensitive storage stays private.
- No generic top-level Book Viewing service.
- No payment activation or paid promotion/packages.
- No Production changes in Phase 1.
- No broad new feature work while establishing the product foundation.

## Work sequencing adjustment

Because W1 visual capture is currently environment-blocked, Phase 1 continues without pretending rendered evidence exists.

W3 is split into smaller units:
- **W3A — Design-system specification:** source-based, no code. Define tokens, typography, spacing, surfaces, controls, states, navigation component rules, and RTL behavior.
- **W3B — Theme/tokens implementation:** Flutter shared foundation only; no broad screen redesign.
- **W3C — Component primitives implementation:** buttons/fields/chips/cards/status/loading/empty/error primitives only.
- **W3V — Visual validation:** deferred until callable Computer Use/emulator access exists; capture real rendered evidence before broad screen rollout.

Do not start W4 until W3A is reviewed and W3B/W3C are accepted at code level. Broad visual rollout remains contingent on later rendered-device validation.