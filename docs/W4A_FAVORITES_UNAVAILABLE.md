# W4a — Favorites unavailable correction (RF01 only)

This source candidate corrects status-unavailable favorites. It does not change listing publication decisions, Financial/Sai, representation, agreements, deployment or database schema.

## API contract

Every Favorites index item has `property_id`, `is_favorited: true`, `favorited_at` and `availability` (`available` or `unavailable`).

- Available: additionally contains the existing public-safe `property` summary.
- Unavailable: additionally contains only a generic `message`. It has no `property` object, title, price, location, media, contact, description, review, evidence, ownership or internal identity fields.
- No approved last-known-public snapshot exists. Current unpublished fields must not be used to label the saved item.

`GET /api/favorites` paginates authenticated account rows, including unavailable favorites, newest favorite ID first. Availability changes never reorder a row or reduce its pagination total. Public properties and their images are fetched in a batch restricted to published rows; unavailable listing fields/media are not loaded.

`GET /api/favorites/ids` returns all property IDs actually saved by the authenticated account, including unavailable items. It does not silently truncate account state at 5,000 IDs.

`GET /api/properties/{property}/favorite`:
- Public property: `property_id`, `is_favorited`, `availability: available`.
- Unpublished property with the caller's favorite: `property_id`, `is_favorited: true`, `availability: unavailable`.
- Unpublished property without the caller's favorite, or unknown ID: the same 404. Listing ownership alone does not reveal private favorite status.

`PUT /api/properties/{property}/favorite` requires a currently published property and remains idempotent. Unpublished and unknown IDs produce the same 404.

`DELETE /api/properties/{property}/favorite` deletes only the caller's row without binding/looking up the Property. It returns the same success shape for saved, already removed, unrelated/private or unknown IDs, echoing only the supplied ID and `is_favorited: false`. This makes removal idempotent and avoids a property-existence oracle.

Favorite routes accept numeric IDs. Existing auth/account-active middleware remains authoritative.

## Flutter

`FavoriteListItem` keeps account identity and availability separate from the optional `PropertyMarker`. An unavailable/unknown state never parses the supplied property summary, even if the response includes stale fields. No fake price, coordinates or media are created.

The unavailable card displays “هذا العقار محفوظ في المفضلة لكنه غير متاح حالياً.” and Remove. It has no details link, compare selector, contact/viewing action, price, location or image. Removal works in normal and compare modes.

Only available favorite IDs count toward the 2–4 compare selection. Each fresh list response prunes missing/unavailable selected IDs before rendering the count. Republishing does not silently re-select an item.

Available cards retain normal details navigation, public summary and comparison. For compatibility with the older API, a missing availability field is accepted only with an explicitly published, identity-matching summary. Explicit unavailable or unknown availability always fails closed.

## Persistence and limits

Published → unpublished → legitimately republished reuses the same favorite row and original saved timestamp. No second save or duplicate row is required.

Hard deletion remains the existing `property_favorites.property_id` cascading FK behavior. A physically deleted Property removes its favorites. No tombstone or snapshot persistence is introduced.

No migration is added or changed: source stays at 48 (47 historical + W3 forward RLS repair); live Supabase stays at 47, with the repair unapplied. W4a does not deploy this candidate or mutate live resources.

## Verification

Backend behavioral tests cover account isolation, unchanged favorite ID/timestamp, stable pagination/IDs, explicit unavailable allowlist, absence of sensitive keys/values, draft/returned/pending/rejected states, unpublished-add rejection, equivalent private/unknown status/add responses, caller-only idempotent removal, hard-delete cascade and blocked details/media/contact/viewing.

Flutter widget tests cover available card/navigation, unavailable visibility/wording/privacy, blocked navigation/compare, removal in both modes, republish and refresh selection cleanup. Repository/model tests exercise authenticated pagination, account changes, unavailable status/removal, republish without PUT and fail-closed decoding.

Full Unified UAT Gate and APK identity must qualify the final PR HEAD; existing W3 parity checks remain required. No merge, Render deploy or live DB apply is authorized by this document.
