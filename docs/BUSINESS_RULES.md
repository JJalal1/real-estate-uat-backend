# Business Rules — REAL ESTATE

These are product rules, not implementation suggestions. Agents should preserve them unless the product owner explicitly changes them.

## 1. Login and basic account

- One login flow for users, based on phone/WhatsApp verification.
- After OTP/profile completion, the default account behaves as a normal browsing/search/buyer account.
- Professional identity is requested later from the account-verification area.

## 2. Professional account types

Supported professional profile types:

- Owner (`owner`)
- Broker (`broker`)
- Real-estate office (`office`)

Operational roles such as support agent, support manager, and platform owner are not professional property-account types.

## 3. Owner verification

- Identity is verified once.
- Relationship to each property is reviewed independently when the property is submitted and proof is required.
- Typical relationship documents may include purchase deed/evidence, registry record where available, partition document, court judgment, inheritance document, ownership contract, agency, partnership, or another appropriate proof.
- If the account name does not match the property document, the user must state the actual relationship such as agent, heir, partner, or other appropriate status.
- Do not label a person as the direct owner when the evidence only supports another relationship.

## 4. Broker verification

- Broker identity/selfie/location/work areas are part of the verification profile.
- Property specializations may be recorded.
- A professional license/document may add an extra professional-verification state.
- A broker is not required to upload ownership evidence for unrelated properties merely to verify the broker account.

## 5. Real-estate office verification

May include the responsible person's identity/selfie, official office name, commercial record, office license, address, map location, office phone, office-front image, and optional logo, according to current implementation.

## 6. Selfie and document capture

- Verification selfie is camera-only.
- Other supported identity/professional documents may offer camera or file selection where the current flow supports both.
- Do not silently downgrade selfie capture to an existing-file upload.

## 7. No broker hierarchy

The following concepts are explicitly rejected:

- master/sub-broker hierarchy
- exclusive broker by region
- head broker for a governorate/area
- broker ownership of a territory
- blocking a verified broker from another governorate solely because of a regional hierarchy

A verified broker may operate across regions under normal review/duplicate/business rules.

## 8. Listing publication and review

- Submission does not automatically mean public publication when review is required.
- New reviewable listings enter the support/review workflow.
- Eligible support staff share the incoming queue.
- The first valid claimant owns the task; backend concurrency protection must prevent double claim.
- Review actions include approve, return for correction with reason, and reject with reason where supported.
- Returned listings must expose the status/reason to the publisher and support resubmission.
- Approved listings become public according to the current workflow.

## 9. Public properties

Published/approved listings are public. Login must not be required merely to browse published properties.

## 10. Support model

- Shared Queue -> Claim is the normal operating model.
- Support manager may assign/reassign/escalate according to backend permissions.
- Platform owner has broader administrative oversight but is not expected to act as a daily support agent.
- A support agent must not gain admin permissions merely from Flutter UI exposure.

## 11. Free product model

The active product is free from the user's perspective.

Do not expose or create an active user journey for:

- paid featured listings
- paid account highlighting
- paid upgrades
- paid marketing packages
- exclusive paid promotion
- paid service tiers

Legacy payment/service structures may stay dormant if deleting them would create unnecessary compatibility or migration risk.

## 12. Services hub

One unified services design is used across verified owner/broker/office accounts. Content varies through backend capabilities.

Current approved direction:

Quick services:

- Add Property
- Request Property
- My Listings
- Value My Property

Property services:

- Property Requests
- Rental Contracts
- Price Indicators
- Property Valuation
- Researcher Requests for eligible verified brokers/offices

Information/tools:

- Real-estate Guide
- Legal Documents

A generic top-level “Book Viewing” service must not be used; viewing starts from a specific property.

## 13. Property Requests — approved design

A real backend entity is required. Intended request fields include operation type, property type, governorate, district, area, budget range, requested area, rooms when relevant, extra specifications, and active duration.

Approved high-level states:

- `active`
- `matched`
- `closed`
- `expired`

A mere broker suggestion should not automatically close the request. State transitions must reflect actual workflow semantics.

## 14. Researcher Requests / suggestions

- Only eligible verified broker/office accounts should see this capability.
- Backend is authoritative.
- A broker/office may suggest only properties it is allowed to act on and which are approved/published/available according to current rules.
- Prevent duplicate suggestion of the same property to the same request unless an explicit business case says otherwise.
- Do not expose sensitive requester contact data merely because a broker can view the request.

Intended journey:

`request -> broker/office match -> property suggestion -> requester notification -> property -> conversation -> viewing request`

## 15. Favorites — approved design

Favorites must be server-side and account-bound, not local-device-only. If a saved property becomes unavailable, keep a clear unavailable state rather than silently disappearing it, and block invalid actions.

## 16. Viewing / booking / conversation

Intended relationship:

`property -> viewing request -> notification -> conversation -> confirm/reschedule/reject/cancel as allowed -> booking visible to both parties`

Booking should know the property, advertiser, requester, related conversation, appointment, status, and history.

## 17. Rental contracts — approved design

Rental contracts must be tied to a real property and parties. Suggested states:

- `draft`
- `awaiting_other_party`
- `agreed`
- `active`
- `expired`
- `cancelled`

Do not describe the contract as government-notarized/official unless a real governmental verification integration exists. Preferred wording after both parties agree: “Confirmed by both parties inside the application.”

## 18. Price indicators and valuation

Both should use one backend data engine and only eligible published/approved platform listings.

Do not include drafts, rejected listings, or unpublished listings in market statistics.

Do not fabricate a valuation when comparable data is insufficient. Return/display an explicit insufficient-data state.

## 19. Legal/guide content

The Real-estate Guide and Legal Documents library are informational. Do not present templates as government-certified or legal advice unless that is genuinely verified. Sensitive/high-risk cases should direct users to an appropriate specialist.
