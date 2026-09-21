# Phase 3 — Buyer Discovery Completion + Server-side Favorites

Status: CLOSED — automated gates passed and product owner accepted the Android candidate on a real device

Canonical tracker: GitHub Issue #13
PR: #15 (`phase3/buyer-discovery-favorites` -> `phase1/ux-product-foundation`)

## Goal

Complete the buyer-side journey on top of the accepted public discovery implementation. Phase 3 does not rebuild messaging, viewing, listing review, payments, contracts, or deferred request/matching features.

## Accepted outcome

### Public discovery boundary
- Anonymous `/properties`, `/properties/nearby`, property details, and media remain published-only.
- Internal listing workflow metadata is no longer included in public summary/detail payloads.
- Owner-only detail responses may include review state/reason, asset/cell identifiers, proof summary, and edit/submit eligibility.
- Search/filter/list/map reuse the existing Laravel/PostGIS discovery path.
- List sorting makes `الأحدث` deterministic (newest property ID first), while price and distance retain explicit modes.

### Server-side Favorites
- Added `property_favorites` with cascading user/property foreign keys and unique `(user_id, property_id)`.
- Favorites are account-bound, idempotent, and Laravel-authoritative.
- API supports list, ID set, single-property status, add, and remove.
- Unpublished properties cannot be newly favorited and disappear from favorite read surfaces.
- Different accounts cannot see each other's favorites.
- Flutter does not access the Supabase table directly.

### Supabase UAT security
- Applied `create_property_favorites_table` to Supabase UAT only.
- RLS is enabled with zero permissive policies.
- Table/sequence privileges are revoked from `PUBLIC`, `anon`, and `authenticated`.
- Security advisor `rls_enabled_no_policy` remains expected for this deny-all direct-access design.
- `unused_index` advisor output remains informational only; indexes are not removed without workload evidence.

### Flutter buyer UX
- Replaced the fake Account -> Favorites action with a real server-backed Favorites screen.
- Added favorite hearts to property details, similar-property cards, search/list results, and the selected-map preview.
- Favorite state comes from the authenticated account and refreshes across surfaces after mutations.
- Anonymous favorite attempts preserve a one-shot internal return location, complete WhatsApp/profile flow when required, return to the same property, and perform the pending favorite once.
- Added explicit loading, empty, error, retry, and unavailable states.

### Share / deep link
- Property share copies `realestate://app/properties/{id}` instead of an incomplete relative path.
- Android registers the owned `realestate://app/properties` deep-link pattern.
- Only the owned scheme/host and positive property IDs are rewritten to internal routes.
- This is an app deep link, not an HTTPS universal link or public website claim.

### Contact advertiser
- Property contact continues to use the single existing `POST /properties/{property}/conversation` path.
- Existing messaging regression coverage verifies property context, participant privacy, and no advertiser self-conversation.
- Deep messaging/viewing hardening remains Phase 4 scope.

## Acceptance evidence

Dedicated workflow: `.github/workflows/phase3-buyer-discovery-ci.yml`

Final accepted GitHub Actions run:
- Phase 3 Buyer Discovery CI run #34 / `34174945119`: SUCCESS.
- Head: `44af494bd3dd586b693903ced5901e9d143f2d90`.
- Laravel regression + explicit Phase 3 API contract: SUCCESS.
- PostgreSQL 17 + PostGIS migration/security + Phase 3 contract: SUCCESS.
- Flutter static analysis + full tests: SUCCESS.
- Compile-time UAT endpoint verification: SUCCESS.
- Release Android APK build/upload: SUCCESS.
- Artifact: `real-estate-phase3-uat-apk-34`.
- Artifact digest: `sha256:3ed8a4f6a8343c6346ff54b6e15a191da9ee32f41901a781ec1edade78cd1631`.

Product owner subsequently installed/tested the Phase 3 Android candidate and explicitly marked Phase 3 accepted on a real device on 2026-09-08.

This acceptance does not by itself prove that the Render service branch/deploy configuration has changed. Live Render UAT deployment/integration state must still be independently verified before claiming Phase 3 backend code is deployed there, and Production remains untouched.

## Out of scope
- Property Requests / Researcher Requests / matching
- payments or paid promotion
- rental contracts
- valuation / price indicators
- legal library
- deep messaging/viewing rebuild
- Production deployment

## Next phase

Phase 4 — property-linked conversation, messaging, viewing, and booking integration hardening.