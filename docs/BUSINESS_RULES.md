# Business Rules — REAL ESTATE

These are product rules, not implementation suggestions. Agents must preserve them unless the product owner explicitly changes them.

## 1. Core marketplace journey

REAL ESTATE is marketplace-first.

Primary journey:

`verified advertiser -> create property -> support review -> publish -> public browse/search/map -> property details -> contact advertiser -> conversation -> viewing -> agreement`

Property Requests / Researcher Requests / broker-driven matching are not part of the launch-critical core journey and are deferred unless explicitly re-approved later.

## 2. Login and basic account

- One login flow for users, based on phone/WhatsApp verification.
- After OTP/profile completion, the default account behaves as a normal browsing/search/buyer account.
- Professional identity is requested later from the account-verification area.

## 3. Professional account types

Supported professional profile types:
- Owner (`owner`)
- Broker (`broker`)
- Real-estate office (`office`)

Operational roles such as support agent, support manager, and platform owner are not professional property-account types.

## 4. Owner verification

- Identity is verified once.
- Relationship to each property is reviewed independently when the property is submitted and proof is required.
- Typical relationship documents may include purchase deed/evidence, registry record where available, partition document, court judgment, inheritance document, ownership contract, agency, partnership, or another appropriate proof.
- If the account name does not match the property document, the user must state the actual relationship such as agent, heir, partner, or other appropriate status.
- Do not label a person as the direct owner when the evidence only supports another relationship.

## 5. Broker verification

- Broker identity/selfie/location/work areas are part of the verification profile.
- Property specializations may be recorded.
- A professional license/document may add an extra professional-verification state.
- A broker is not required to upload ownership evidence for unrelated properties merely to verify the broker account.

## 6. Real-estate office verification

May include the responsible person's identity/selfie, official office name, commercial record, office license, address, map location, office phone, office-front image, and optional logo, according to current implementation.

## 7. Selfie and document capture

- Verification selfie is camera-only.
- Other supported identity/professional documents may offer camera or file selection where the current flow supports both.
- Do not silently downgrade selfie capture to an existing-file upload.

## 8. No broker hierarchy

Explicitly rejected:
- master/sub-broker hierarchy;
- exclusive broker by region;
- head broker for a governorate/area;
- broker ownership of a territory;
- blocking a verified broker from another governorate solely because of a regional hierarchy.

A verified broker may operate across regions under normal review/duplicate/business rules.

## 9. Listing publication and review

- Submission does not automatically mean public publication when review is required.
- New reviewable listings enter the support/review workflow.
- Eligible support staff share the incoming queue.
- The first valid claimant owns the task; backend concurrency protection must prevent double claim.
- Review actions include approve, return for correction with reason, and reject with reason where supported.
- Returned listings must expose the status/reason to the publisher and support resubmission.
- Approved listings become public according to the current workflow.

## 10. Duplicate physical property rule

- The same physical property must not be published more than once at the same time.
- Current backend `PropertyAsset` identity and publication checks are authoritative.
- Duplicate prevention must be enforced server-side at submission/approval boundaries, not only by Flutter UI.
- Future similarity detection may flag likely duplicates even when address/location/details are slightly altered, but it must not silently merge unrelated properties.
- Support must retain an auditable way to review/link likely duplicate listings where needed.

## 11. Public properties

Published/approved listings are public. Login must not be required merely to browse published properties.

## 12. Discovery and property details

- Browsing/search/filter/map are the primary discovery mechanisms for buyers/renters.
- Property details are the main conversion surface.
- Save/share/contact/viewing actions should stay contextual to the selected property when applicable.
- A property that is no longer published/available must not silently behave as active.

## 13. Support model

- Shared Queue -> Claim is the normal operating model.
- Support manager may assign/reassign/escalate according to backend permissions.
- Platform owner has broader administrative oversight but is not expected to act as a daily support agent.
- A support agent must not gain admin permissions merely from Flutter UI exposure.

## 14. Free product model

The active product is free from the user's perspective.

Do not expose or create an active user journey for:
- paid featured listings;
- paid account highlighting;
- paid upgrades;
- paid marketing packages;
- exclusive paid promotion;
- paid service tiers.

Legacy payment/service structures may stay dormant if deleting them would create unnecessary compatibility or migration risk.

Money movement between parties (rent, deposit, commission, escrow, etc.) is not currently an approved launch requirement and must be treated as a separate future product/security/legal phase if requested.

## 15. Services hub

One unified services design is used across verified owner/broker/office accounts. Content varies through backend capabilities.

Launch-relevant service direction:
- Add Property
- My Listings
- Rental Contracts (later phase)
- Price Indicators (later phase)
- Property Valuation (later phase)
- Real-estate Guide
- Legal Documents

Do not surface Property Requests / Researcher Requests as launch-critical core services unless the product owner explicitly re-approves them.

A generic top-level “Book Viewing” service must not be used; viewing starts from a specific property.

## 16. Favorites

Favorites must be server-side and account-bound, not local-device-only. If a saved property becomes unavailable, keep a clear unavailable state rather than silently disappearing it, and block invalid actions.

## 17. Viewing / booking / conversation

There is one property-linked messaging system. Do not build a second chat or a parallel viewing conversation.

Canonical relationship:

`property -> contact/conversation -> viewing request -> notification -> confirm | reschedule | reject | cancel -> viewing -> complete`

Rules:
- A new property conversation or viewing request requires the property to be currently published and the advertiser to be available.
- An existing conversation/history remains accessible to its participants if the property later becomes unpublished; the UI must clearly show that the listing is no longer published.
- Conversation content is private to participants. Support access to private message content is allowed only through the reported-conversation workflow with the required permission and an auditable access event.
- Message delivery must be retry-safe. A client message key may identify one logical message; reusing the same key for a different body is a conflict.
- Long conversations must return the newest messages first through a bounded page and allow older history to be loaded without dropping the latest messages.
- Read/unread state is server-authoritative.
- A viewing request belongs to the real property/requester/advertiser and, for property viewings, the related message thread.
- Initial requester proposals are confirmed or rejected by the advertiser.
- If the advertiser reschedules, the new time returns to `requested` and must be explicitly accepted by the requester; the advertiser cannot confirm its own replacement proposal.
- If the requester reschedules, the advertiser confirms the new proposal.
- Either allowed party may cancel while the booking is active; completed/declined/cancelled terminal states cannot be reopened by a normal state action.
- A confirmed viewing can only be marked completed after its scheduled end.
- Overlapping confirmed target/requester/host schedules are rejected by the backend; concurrency decisions are server-authoritative.
- Viewing notifications and app links should open the exact conversation or booking target when the reference is available.

Booking records should preserve:
- property or supported development-unit target;
- advertiser/host;
- requester;
- related conversation where applicable;
- proposed/confirmed appointment;
- status;
- immutable change history.

## 18. Rental contracts

Rental contracts must be tied to a real property and parties.

Suggested states:
- `draft`
- `awaiting_other_party`
- `agreed`
- `active`
- `expired`
- `cancelled`

Do not describe the contract as government-notarized/official unless a real governmental verification integration exists. Preferred wording after both parties agree: “Confirmed by both parties inside the application.”

## 19. Price indicators and valuation

Both should use one backend data engine and only eligible published/approved platform listings.

Do not include drafts, rejected listings, or unpublished listings in market statistics.

Do not fabricate a valuation when comparable data is insufficient. Return/display an explicit insufficient-data state.

## 20. Legal/guide content

The Real-estate Guide and Legal Documents library are informational. Do not present templates as government-certified or legal advice unless that is genuinely verified. Sensitive/high-risk cases should direct users to an appropriate specialist.
