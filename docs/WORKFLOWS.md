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

## 3. Listing publication

High-level product path:

`create listing -> enter property data/media/location/required evidence -> submit -> shared support review queue -> support claim -> review -> approve | return for correction | reject`

If returned:

`publisher sees reason -> edits -> resubmits -> review resumes`

If approved:

`published -> visible in public property browsing`

Use current backend enum names before coding; do not invent a parallel status system.

## 4. Support shared queue

Normal behavior:

`new item -> visible to eligible support staff -> one agent claims -> backend atomically assigns -> item leaves other agents' unassigned queue -> claimant sees it in My Tasks`

Manager behavior may include assign/reassign/reopen/escalate based on permissions.

Concurrent claim attempts must be decided by backend state/transaction logic. Flutter alone is insufficient.

## 5. Property Requests — planned Phase 2

Intended flow:

`user -> Request Property -> create persistent request -> active request appears in user's Property Requests`

Typical filters/data:

- buy/rent
- property type
- governorate
- district
- area
- budget min/max
- desired area
- rooms when relevant
- additional specifications
- active duration

User capabilities:

- list own requests
- open details
- edit while allowed
- close when no longer needed
- see active/matched/closed/expired state

## 6. Researcher Requests — planned Phase 2

Eligibility:

- verified broker or verified real-estate office
- backend capability/authorization required

Flow:

`broker/office -> Researcher Requests -> suitable active request -> Suggest Property -> choose from own allowed approved/published properties -> submit suggestion`

Then:

`requester gets notification -> opens suggested property -> property details -> conversation -> viewing request`

Protect against duplicate suggestion of the same property/request pair unless explicitly allowed later.

## 7. Favorites — planned

`property heart -> backend favorite(user_id, property_id) -> Favorites list`

Cross-device behavior is required.

If property becomes unavailable:

`favorite remains explainable -> show unavailable state -> disable invalid property actions`

Do not silently discard it from the user's history unless product rules later require cleanup.

## 8. Viewing and bookings

Viewing starts from a property:

`property -> request viewing -> proposed date/time -> advertiser notification -> create/open related conversation -> advertiser confirms/reschedules/rejects -> requester sees every state change -> booking visible to both parties`

Expected linkages:

- property
- advertiser
- requester
- conversation/thread
- proposed/confirmed appointment
- status
- change history

## 9. Rental contracts — planned

Preferred journey:

`listing -> viewing -> conversation/agreement -> create rental contract -> other party confirms -> agreed/active contract`

Contract references:

- property
- landlord
- tenant
- rent value/currency
- optional deposit
- start/end dates
- payment frequency
- terms/notes
- related conversation where appropriate

No government-verification claim without real integration.

## 10. Price indicators — planned

Input filters may include:

- governorate
- district
- area
- property type
- sale/rent

Use only published/approved eligible platform listings.

Potential output:

- average price
- average price per square unit when meaningful
- common range
- median
- sample size

Always communicate sample scope.

## 11. Property valuation — planned

Use the same backend engine/data rules as price indicators.

`user chooses own property or enters property facts -> backend finds comparable eligible listings -> returns approximate range or insufficient-data result`

Never generate a fake market estimate if data is inadequate.

## 12. Notifications/deep links

Workflow notifications should contain enough reference data to open the actual entity/step, not only a generic notifications page.

Examples:

- suitable property request
- property suggestion
- viewing request
- viewing confirmation/reschedule/cancel
- message related to a request/property
- contract confirmation request
- contract state change

Deep-link handling must still respect authorization when the target opens.
