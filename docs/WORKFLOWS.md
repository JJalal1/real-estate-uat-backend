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

The launch-critical product path is:

`verified advertiser -> create listing -> enter property data/media/location/required evidence -> duplicate-property checks -> submit -> shared support review queue -> support claim -> review -> approve | return for correction | reject`

If returned:

`publisher sees reason -> edits -> resubmits -> review resumes`

If approved:

`published -> public browse/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Use current backend enum names before coding; do not invent a parallel status system.

## 4. Duplicate physical property workflow

Current server-side behavior uses `PropertyAsset` identity and checks publication state before approval.

Required behavior:

`listing facts -> resolve/create physical property identity -> check active publication/block -> submit/review -> re-check during approval transaction -> publish only if allowed`

If a likely duplicate cannot be proven automatically, future similarity tooling may flag it for support review. Do not silently merge unrelated properties.

## 5. Support shared queue

Normal behavior:

`new item -> visible to eligible support staff -> one agent claims -> backend atomically assigns -> item leaves other agents' unassigned queue -> claimant sees it in My Tasks`

Manager behavior may include assign/reassign/reopen/escalate based on permissions.

Concurrent claim attempts must be decided by backend state/transaction logic. Flutter alone is insufficient.

## 6. Public discovery

Published properties are browsable without login.

Primary buyer/renter path:

`open app -> browse/search/filter/map -> open property -> inspect gallery/details/advertiser -> save/share/contact as available`

Unavailable/unpublished properties must show an explicit state and block invalid actions.

## 7. Favorites — planned launch-critical enhancement

`property heart -> backend favorite(user_id, property_id) -> Favorites list`

Cross-device behavior is required.

If property becomes unavailable:

`favorite remains explainable -> show unavailable state -> disable invalid property actions`

Do not silently discard it from the user's history unless product rules later require cleanup.

## 8. Conversation and viewing

Viewing starts from a property:

`property -> contact/open conversation -> request viewing -> proposed date/time -> advertiser notification -> advertiser confirms/reschedules/rejects -> requester sees every state change -> booking visible to both parties`

Expected linkages:
- property;
- advertiser;
- requester;
- conversation/thread;
- proposed/confirmed appointment;
- status;
- change history.

## 9. Rental contracts — planned launch-critical phase

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

## 10. Price indicators — planned

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

## 11. Property valuation — planned

Use the same backend engine/data rules as price indicators.

`user chooses own property or enters property facts -> backend finds comparable eligible listings -> returns approximate range or insufficient-data result`

Never generate a fake market estimate if data is inadequate.

## 12. Guide and legal content

Real-estate Guide and Legal Documents are informational tools. They must not be presented as government certification or legal advice without a real verified integration/source.

## 13. Notifications/deep links

Workflow notifications should contain enough reference data to open the actual entity/step, not only a generic notifications page.

Examples:
- listing review state change;
- message related to a property;
- viewing request;
- viewing confirmation/reschedule/cancel;
- contract confirmation request;
- contract state change.

Deep-link handling must still respect authorization when the target opens.

## 14. Deferred request/matching concept

Property Requests, Researcher Requests, and broker-driven suggestion/matching are deferred and are not a launch-critical prerequisite. Do not implement or expose them as the main journey unless explicitly re-approved by the product owner.
