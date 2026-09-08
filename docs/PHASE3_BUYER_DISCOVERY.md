# Phase 3 — Buyer Discovery Completion + Server-side Favorites

Status: IN PROGRESS — automated acceptance gates running

Canonical tracker: GitHub Issue #13
Draft PR: #15 (`phase3/buyer-discovery-favorites` -> `phase1/ux-product-foundation`)

## Goal

Complete the buyer-side journey on top of the accepted public discovery implementation. Phase 3 does not rebuild messaging, viewing, listing review, payments, contracts, or deferred request/matching features.

## Implemented

### Public discovery boundary
- Anonymous `/properties`, `/properties/nearby`, property details, and media remain published-only.
- Internal listing workflow metadata is no longer included in public summary/detail payloads.
- Owner-only detail responses may include review state/reason, asset/cell identifiers, proof summary, and edit/submit eligibility.
- Search/filter/list/map reuse the existing Laravel/PostGIS discovery path.
- List sorting now makes `الأحدث` deterministic (newest property ID first), while price and distance retain their explicit modes.

### Server-side Favorites
- Added `property_favorites` with cascading user/property foreign keys and unique `(user_id, property_id)`.
- Favorites are account-bound, idempotent, and Laravel-authoritative.
- API supports list, ID set, single-property status, add, and remove.
- Unpublished properties cannot be newly favorited and disappear from favorite read surfaces.
- Different accounts cannot see each other's favorites.
- Flutter does not access the Supabase table directly.

### Supabase UAT security
- Applied `create_property_favorites_table` to Supabase UAT only.
- RLS is enabled.
- No permissive RLS policies were created.
- Table/sequence privileges are revoked from `PUBLIC`, `anon`, and `authenticated`.
- Security advisor `rls_enabled_no_policy` is expected for this deny-all direct-access design.
- `unused_index` advisor output is informational only and is not evidence to remove launch-supporting indexes without workload data.

### Flutter buyer UX
- Replaced the fake Account -> Favorites action with a real server-backed Favorites screen.
- Added favorite hearts to property details, similar-property cards, search/list results, and the selected-map preview.
- Favorite state comes from the authenticated account and refreshes across surfaces after mutations.
- Anonymous favorite attempts preserve a one-shot internal return location, complete WhatsApp/profile flow when required, return to the same property, and perform the pending favorite once.
- Added explicit loading, empty, error, and retry states for Favorites.

### Share / deep link
- Property share now copies `realestate://app/properties/{id}` instead of an incomplete relative path.
- Android registers the owned `realestate://app/properties` deep-link pattern.
- Only the owned scheme/host and positive property IDs are rewritten to internal routes.
- This is an app deep link, not an HTTPS universal link or public website claim.

### Contact advertiser
- Property contact continues to use the single existing `POST /properties/{property}/conversation` path.
- Existing messaging regression coverage verifies property context, participant privacy, and no advertiser self-conversation.
- Deep messaging/viewing hardening remains Phase 4 scope.

## Automated acceptance

Dedicated workflow: `.github/workflows/phase3-buyer-discovery-ci.yml`

Required gates:
1. full Laravel regression + explicit Phase 3 API contract;
2. PostgreSQL 17 + PostGIS full migration/security regression + Phase 3 contract;
3. Flutter static analysis + full widget/unit suite;
4. compile-time UAT endpoint verification;
5. release Android APK build/upload.

New focused coverage includes:
- account isolation/idempotency/unpublished behavior for Favorites;
- public discovery privacy boundary;
- deep-link parsing/ownership;
- one-shot auth return intent;
- Favorites empty and populated server-backed UI states.

Do not mark Phase 3 CLOSED until the latest branch HEAD passes all required gates. Real-device end-to-end Favorites acceptance additionally requires a UAT API deployment containing the new backend routes; the current Render UAT service still tracks the older stabilization branch and auto-deploy is disabled.

## Out of scope
- Property Requests / Researcher Requests / matching
- payments or paid promotion
- rental contracts
- valuation / price indicators
- legal library
- deep messaging/viewing rebuild
- Production deployment
