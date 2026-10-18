# Business Rules — REAL ESTATE

## October18 current-wave input and location decisions

New professional Sai input defaults to a fixed amount; existing explicit saved/immutable choices retain their type. Fixed input shows Arabic money words and the compact notice that the platform share is charged to the broker. Percentage input cannot exceed100%; the existing stricter sale ceiling still applies. Owner rates, financial formulas, payer, zero fallback, explicit attestation and all historical records remain unchanged.

The current apartment selector/writes accept ground through seventh only. Office choices and historical read labels remain. First Home requests foreground location with the system prompt; remember a denied/resolved prompt across launches. Manual city choice persists and wins over delayed GPS until explicitly changed. New discovery journeys use Home's location as a default, while explicit city/map/saved searches override it. Location context does not restore old search text/results or trigger a search before user action. Description remains inline, one request per press, editable, and waits for Retry-After following429 without an automatic request loop.

## Wave6 accepted scope — October18

Use the central property schema across all input/discovery/detail/compare surfaces. Shop area is sqm; apartment floor is a choice. Account checkpoints allow partial inputs, remain private and cannot publish or accept Sai. Voice keeps manual stop, editable review and explicit application; reviewed suggestions lead to missing-required-fields completion. Inline descriptions use reviewed facts and protect subsequent user edits from late results.

The compact Sai summary uses actual backend policy and keeps fixed/percentage amounts, owner rates, zero fallback, split, payer, immutable history and explicit financial consent. Comparison uses factual compatible values, replacement/removal and dynamic groups. Full search exit clears the journey; only explicitly chosen saved searches restore it. Home uses actual data/location. Broker contact reuses private messaging without implicit messages; closed sold/rented listing counts stay distinct from confirmed deals. Retain rent7/sale14/grace2 availability. Provider503 must remain visible and must not be reported as successful AI interpretation.

These are product rules, not implementation suggestions. Agents must preserve them unless the product owner explicitly changes them.

## October16 supplied voice reference

The new reference authorizes live dictation previews in the existing text input for search and listing preparation. Preserve typed context, manual finish, edit/review and explicit send; neither pauses nor partial callbacks may execute a search or write listing facts. Cancel/error restores the original brief and does not save temporary hypotheses. Internal finalized recognition segments may accumulate while the user session stays active. Android system dictation can depend on a network service; do not promise offline/on-device recognition. The old full-clip Laravel transcription remains the fallback where no recognition service exists. Search chips, actual results, organized Home sections and advertiser review/financial rules remain. See `VOICE_REFERENCE_20261016_AR.md`.

## October16 delegated broker assistance

Listing AI proposes only reviewable facts/title/description; it cannot save, approve or publish a listing. Recompose copy after changing selected proposals. Preserve raw brief locally per user/listing. Provider failure may use conservative literal-text organization only when labeled clearly. Voice transcription still depends on its provider. Completion guidance uses existing required-field/photo/identity/Sai checks. Copying public ad text is an explicit clipboard action; no automated messages or private evidence/financial splits. See `BROKER_AI_ASSISTANT_AR.md`.

## Current October16 Wave5 on1049

The owner confirmed current1049. Listing input7 hides rental-apartment area/elevator and makes position optional; known historical identity/facts remain. Unspecified units require an auditable support identity decision rather than an invented unit or shared whole-floor asset. Rental conditions use inline chips and reveal only selected details.

Professional Sai supports percentage or native fixed amounts. Owner rates, zero fallback, payer and internal split remain. Fixed fees are bounded at configuration/review by the equivalent current percentage ceiling and frozen in their original currency; final deal-price changes do not recalculate the fee. Mixed inputs and currency mismatches are rejected. Explicit consent and customer-confirmed outcomes remain mandatory. Home and Account open the existing smart-search session through lightweight entries; no full AI block remains on Home.

## Earlier October15 Wave4 changes

Wave4 starts from APK1039. The active viewing/booking UI, endpoints and notifications are retired; parties coordinate visits using ordinary property-linked messages. Historical bookings/events/messages and all immutable financial history stay intact; no replacement calendar is authorized.

Listing input6 moves mandatory photos and editable fact-grounded description to specifications, removes new whole-floor selection, makes area optional for rental apartments, and stores only selected optional rental requirements. Existing whole-floor identity is preserved read-only for legacy listings. Step4 shows rate/total and visible Previous, without display-mode choice, split or consent checkbox. Public price/rate are automatic. Existing rates, monthly commission basis and customer payer remain. New pending custom terms may enter review, but settlement requires the existing explicit post-publication attestation tied to the immutable term. No implicit acceptance is created.

Voice capture ends by the user's stop action, not silence. The complete temporary clip is transcribed on Laravel with the existing server-only Gemini configuration. Text, voice and chips update one search state; resource-limit/error paths never execute a partial request. No TTS or background recording is authorized.

## Earlier October13 refinement

New Sai configurations are paid by the customer (sale buyer / rental tenant), with the existing rates, zero-rate fallback, internal split and explicit platform-condition acceptance. Immutable historical conversation/financial terms are retained. Advertisers start in the normal marketplace and reach their separate work area explicitly. See `UX_REFINEMENT_ROUND2_AR.md` for dynamic listing scope and the new read-only editor policy contract. Historical planned contract text below does not enable new contract creation.

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

## 21. October 13 Wave3 account and unit scope

The first listing step offers basic types only; a whole-floor unit is an apartment with `unit_occupies_entire_floor`, not a separate first-step category. It requires a floor, clears a unit position, and uses the existing `@whole_floor` identity marker. Old `floor` listings remain readable/editable and match apartment searches. Whole buildings/houses/villas discard irrelevant floor/unit fields.

A modern ordinary account needs the existing owner verification before publishing one personal property. Any non-archived personal listing, including a draft, consumes that slot; editing/resuming it does not create another slot. A second creation is rejected by the backend under a user-row transaction lock and offers broker review. Approved brokers/offices can manage multiple listings and use the work/CRM screens. An approved owner retains owned-property availability, conversation/viewing/outcome actions and platform receivables without getting professional CRM. Broker activation is free and grants tools only after normal verification approval; registration remains ordinary.

The historical v0 local/test listing compatibility is retained; modern registration cannot request it. No commission formulas, financial snapshots, hierarchy, contracts or public/private storage boundaries change.
