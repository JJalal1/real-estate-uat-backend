# Phase 1 — Accepted Information Architecture

Status: ACCEPTED AND IMPLEMENTED
Branch: `phase1/ux-product-foundation`

## Launch-critical product journey

`verified advertiser -> create property -> support review -> publish -> public discovery/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / matching are deferred and must not drive primary navigation, launch-facing quick actions, or active services capabilities unless explicitly re-approved.

## Accepted consumer navigation

### Anonymous visitor
- العقارات
- حسابي

Published properties and property details remain browsable without login. Authentication is requested only when an action requires an account.

### Regular authenticated user
- العقارات
- الرسائل
- المعاينات
- حسابي

### Verified owner / broker / real-estate office
- العقارات
- إعلاناتي
- الرسائل
- المعاينات
- حسابي

Professional type changes capability/content, not the overall marketplace shell. Backend authorization remains authoritative.

## Accepted operational navigation

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

### Platform owner
- لوحة الإدارة
- المراجعات
- المستخدمون
- المنصة
- حسابي

## Accepted destination placement

- Public map/list/search/filter remains one top-level `العقارات` destination.
- `إعلاناتي` is a top-level advertiser destination for verified owner/broker/office profiles.
- `إضافة عقار` is an action inside My Listings and may have contextual shortcuts to the same canonical route.
- Messages remains one canonical inbox/conversation system.
- Viewing is labeled `المعاينات`; creation always starts from a specific property.
- Account contains profile, authentication/recovery, professional verification, notifications, personal help/support, and secondary tools.
- Services stays under Account as `الخدمات والأدوات`; it is not a bottom-navigation tab.
- Consumer support cases remain under Account -> `المساعدة والدعم`.
- Favorites is not promoted to a top-level tab before the server-side account-bound implementation exists.
- Property Requests / Researcher Requests / matching receive no primary tab, quick-card treatment, or active server capability in the launch surface.
- Contracts, price indicators, valuation, guide, and legal documents remain approved later service directions until implemented.
- Operational users may later receive a clear secondary `تصفح العقارات` entry without replacing their operational default shell.

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

## Context-preservation requirements

Later hardening should:
- preserve property/action return context through authentication;
- preserve booking/task/listing entity identifiers through notifications and dashboard shortcuts;
- give primary shell destinations stable route identities while preserving compatible existing URLs;
- distinguish consumer help from staff support work clearly.

## Constraints unchanged

- Backend authorization is authoritative.
- Published properties remain public.
- No broker hierarchy or regional exclusivity.
- Shared queue -> claim remains the support model.
- Sensitive storage stays private.
- No generic top-level Book Viewing service.
- No payment activation or paid promotion/packages.

## Closure note

The information architecture is no longer a planning target; it is the accepted Phase 1 baseline. Real-device visual validation remains a Beta/launch-readiness gate and does not block starting Phase 2.
