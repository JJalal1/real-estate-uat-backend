# Workflows — REAL ESTATE

## 1. Login and account identity

`phone/WhatsApp verification -> profile completion -> basic browsing/search/buyer account`

Professional identity is requested separately through the account-verification flow. Do not require a user to choose owner/broker/office during basic login unless the product owner explicitly changes that rule.

## 2. Professional verification

### Owner

`choose owner -> identity/location/selfie -> submit -> support queue -> claim -> approve/request more/reject`

Once owner identity is approved, identity should not be re-verified for every listing. Property relationship evidence remains listing-specific when required.

### Broker

`choose broker -> identity/location/work areas/specializations/selfie/optional professional doc -> submit -> support queue -> claim -> approve/request more/reject`

### Real-estate office

`choose office -> responsible-person identity/selfie -> office registry/license/details/location/media -> submit -> support queue -> claim -> approve/request more/reject`

After submission, prevent accidental duplicate submission while the same request is pending unless the workflow explicitly supports resubmission after a requested correction.

## 3. Core marketplace journey

The hardened listing path is:

`verified advertiser -> create/edit property facts -> save draft -> media -> location -> required property-specific evidence -> preview -> explicit submit -> duplicate checks/signals -> shared support review queue -> support claim -> evidence review -> approve | return for correction | reject`

Draft and submission are separate user decisions. Preview is non-mutating.

If returned:

`publisher sees support reason -> edits the same returned_for_correction listing -> reason remains visible -> explicit resubmit -> review resumes`

If approved:

`server re-checks advertiser eligibility + publication block + exact physical-property duplicate + region -> publish -> advertiser notification -> public browse/search/map -> property details -> favorite/share/contact -> conversation -> viewing -> agreement`

Use current backend enum names before coding; do not invent a parallel status system.

## 4. Duplicate physical property workflow

Exact server-side protection uses `PropertyAsset` identity and publication checks:

`listing facts -> resolve/create physical property identity -> check active publication/block -> submit/review -> lock listing + asset during approval -> re-check -> publish only if allowed`

Phase 2 also adds explainable likely-duplicate review:

`submitted listing -> compare same-type nearby reviewable/published listings -> score geographic proximity + normalized address + area + bedroom/bathroom similarity -> show candidates to support`

Likely similarity never silently merges or fuzzy-rejects an uncertain property. When candidates exist, support must either:
- record an auditable reason explaining why the candidate is a different physical property before approval; or
- link the listing to the correct existing `PropertyAsset` with a reason.

After linking, the normal exact duplicate/block rules remain authoritative.

## 5. Support shared queue and listing review

Normal behavior:

`new item -> visible to eligible support staff -> one agent claims -> backend atomically assigns -> item leaves other agents' unassigned queue -> claimant sees it in My Tasks`

For listing review, evidence-first handling is:

`claim -> inspect advertiser verification + property facts + public media + private relationship evidence + likely-duplicate candidates + review history -> approve | return | reject`

A support worker must own the claimed listing before a sensitive review decision. Managers retain their existing oversight permissions. Concurrent claim and decision attempts are decided by backend locks/state, never Flutter visibility alone.

## 6. Listing evidence and media

- Public listing images are separate from private verification/evidence documents.
- A listing needs at least one public image before submission.
- Owner relationship evidence is property-specific and is collected inside the canonical listing editor.
- Owner evidence includes the relevant document type, document owner name, relationship type/note where needed, and private proof file.
- Verified brokers/offices do not receive unrelated ownership requirements.
- Private documents are accessible only through authorized endpoints and audited review context.
- Draft media may be replaced/reordered through the supported editor behavior without exposing private evidence as public media.

## 7. Listing notifications

The advertiser receives property-linked notifications for the review outcomes that require attention:
- returned for correction;
- approved/published;
- final rejection/block.

The entity reference is the real property/listing. Notification deep links still pass through authorization and current availability rules.

## 8. Public discovery

Published properties are browsable without login.

Primary buyer/renter path:

`open app -> browse/search/filter/map -> open property -> inspect gallery/details/advertiser -> save/share/contact as available`

Draft, submitted, under-review, returned, or rejected listings remain outside public discovery. Approved publication makes the listing publicly readable. Unavailable/unpublished properties must show an explicit state and block invalid actions.

## 9. Favorites

`property heart -> backend favorite(user_id, property_id) -> Favorites list`

Favorites are account-bound server state and work across devices.

If property becomes unavailable:

`favorite remains explainable -> show unavailable state -> disable invalid property actions`

Do not silently discard it from the user's history unless product rules later require cleanup.

## 10. Conversation and viewing

Viewing starts from a specific property and reuses the single property-linked conversation system.

### Conversation entry

`published property -> contact -> resolve/reuse conversation(property + participant pair)`

- New contact is blocked when the property is no longer published.
- Existing participant conversation/history remains available after later unpublication with an explicit unavailable-listing state.
- Normal private-content access is participant-only.
- Support private-content access requires an active conversation report + dedicated permission and creates an auditable access event.

### Message delivery

`compose -> client_message_id -> server transaction -> create once -> recipient notification`

If a request is retried with the same `client_message_id` and same body, return the existing logical message without duplicate delivery. The same key with a different body is a conflict.

Conversation history:

`open thread -> newest 100 messages -> optional before_id -> load older page -> merge without duplicate ids`

Opening the newest page marks current visible conversation state read; loading an older page does not move the read marker backwards.

### Initial viewing request

`requester proposes time -> requested -> advertiser confirm | advertiser reject | allowed party cancel`

### Requester reschedule

`requested|confirmed -> requester proposes new time -> requested -> advertiser confirms | advertiser rejects | allowed party cancels`

### Advertiser reschedule

`requested|confirmed -> advertiser proposes new time -> requested -> requester explicitly accepts | requester proposes another time | allowed party cancels`

The advertiser cannot self-confirm its own replacement time.

### Completion

`confirmed -> scheduled end passes -> authorized host/manager marks completed`

`completed`, `declined`, and `cancelled` are terminal for normal booking actions.

Backend transactions/locks decide concurrent booking state and overlap conflicts. Flutter controls are not authorization.

Expected linkages:
- target property or supported development unit;
- advertiser/host;
- requester;
- message thread for property viewings;
- proposed/confirmed appointment;
- status;
- immutable event history.

## 11. Rental contracts — planned launch-critical phase

Preferred journey:

`listing -> viewing -> conversation/agreement -> create rental contract -> other party confirms -> agreed/active contract`

Contract references:
- property;
- landlord;
- tenant;
- rent value/currency;
- optional deposit;
- start/end dates;
- payment frequency;
- terms/notes;
- related conversation where appropriate.

No government-verification claim without real integration.

## 12. Price indicators — planned

Input filters may include:
- governorate;
- district;
- area;
- property type;
- sale/rent.

Use only published/approved eligible platform listings.

Potential output:
- average price;
- average price per square unit when meaningful;
- common range;
- median;
- sample size.

Always communicate sample scope.

## 13. Property valuation — planned

Use the same backend engine/data rules as price indicators.

`user chooses own property or enters property facts -> backend finds comparable eligible listings -> returns approximate range or insufficient-data result`

Never generate a fake market estimate if data is inadequate.

## 14. Guide and legal content

Real-estate Guide and Legal Documents are informational tools. They must not be presented as government certification or legal advice without a real verified integration/source.

## 15. Notifications/deep links

Workflow notifications contain enough reference data to open the actual entity/step rather than only a generic notifications page.

Phase 4 routing:
- message/property-viewing notification with `message_thread_id` -> exact conversation;
- standalone viewing notification with `booking_id` -> `/bookings?booking={id}` and highlighted booking;
- property notification -> exact property when available.

Owned application links include:
- `realestate://app/properties/{id}`;
- `realestate://app/messages/{threadId}`;
- `realestate://app/bookings/{bookingId}`.

Private deep-link targets always pass authentication/authorization after routing.

## 16. Deferred request/matching concept

Property Requests, Researcher Requests, and broker-driven suggestion/matching are deferred and are not a launch-critical prerequisite. Do not implement or expose them as the main journey unless explicitly re-approved by the product owner.
