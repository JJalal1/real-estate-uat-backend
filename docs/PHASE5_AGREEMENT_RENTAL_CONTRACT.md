# Phase 5 — Agreement + Rental Contract Journey

Status: IN PROGRESS

Branch: `phase5/agreement-rental-contract`
Canonical issue: #19
Target integration branch: `phase1/ux-product-foundation`

## Product boundary

Phase 5 completes the post-viewing transaction journey inside REAL ESTATE. The records created by this phase are **in-app commercial records only**. They are not represented as government notarization, title registration, deed transfer, escrow, legal certification, or legal advice.

No real payment/deposit transfer, paid packages, matching/property requests, valuation, Production deployment, or merge to `main` is part of this phase.

## Canonical journey

`published property -> property-linked conversation -> viewing (when used) -> agreement draft -> review terms -> both parties accept the same revision -> accepted agreement -> rental only: rental contract draft -> both parties accept the same contract revision -> active in-app rental contract record`

A viewing is optional for the agreement workflow. The authoritative relationship is the existing property-linked conversation between the property advertiser and the other participant. A completed viewing may be linked when one exists.

## Agreement contract

- One active agreement workflow per property + property-linked conversation.
- The agreement records the property, message thread, requester party and advertiser party.
- Every material set of terms is an immutable revision.
- A party acceptance belongs to one exact revision.
- Editing terms creates a new revision; prior revision acceptances never carry forward.
- The agreement becomes accepted only when both parties have accepted the same current revision.
- Accepted agreement revisions cannot be edited in place.
- Either participant may cancel an agreement before final acceptance; accepted agreements remain historical records and are not silently deleted.
- Sale transactions stop at accepted agreement in Phase 5.

Minimum agreement terms:
- transaction type copied from property purpose (`sale` or `rent`);
- agreed amount and currency;
- optional human-readable conditions/notes;
- rental cadence when applicable;
- optional recorded security-deposit amount when applicable (record only; no money movement);
- proposed rental start/end dates when applicable.

## Rental contract contract

Only an accepted agreement for a rental property can create a rental contract.

- One rental-contract workflow per accepted agreement.
- Contract terms are revisioned and immutable after acceptance.
- Both the tenant/requester party and advertiser/lessor side explicitly accept the same current revision.
- Both-party acceptance moves the record to `active` as an **in-app contract record**.
- The system does not claim notarization, official registration, enforceability, or governmental approval.
- Termination/cancellation is recorded as metadata/history; accepted history is never destroyed.

Minimum rental-contract terms:
- agreed rent amount/currency/cadence;
- start date and end date;
- optional recorded security-deposit amount;
- payment due day when supplied (schedule metadata only; no payment processing);
- free-text additional terms with bounded length;
- property and both-party identity snapshots for historical readability.

## Authorization and privacy

- Only the two participants in the canonical property conversation can read agreement/contract content through normal user APIs.
- The advertiser party is the property owner/advertiser user for the listing; the other conversation participant is the requester/buyer/tenant party.
- Users cannot create an agreement with themselves.
- Agreement/contract IDs are never sufficient authorization; every read/write re-checks party membership.
- Public property APIs never expose agreement or contract terms.
- Backend authorization is authoritative; Flutter action visibility is convenience only.

## Concurrency and integrity

- Creation, revision, acceptance, cancellation and contract activation use database transactions with row locking.
- PostgreSQL partial unique indexes prevent duplicate non-terminal workflows for the same canonical relationship.
- Both-party acceptance is calculated under lock against the exact current revision.
- A stale client attempting to accept an older revision receives a conflict response.
- Revision numbers are monotonic per agreement/contract.
- Audit events record creation, revision, acceptance, cancellation, activation and termination without storing secrets.

## Notifications and app links

Agreement and rental-contract lifecycle notifications carry exact target IDs and open owned app links:
- `realestate://app/agreements/{agreementId}`
- `realestate://app/rental-contracts/{contractId}`

Private destinations still pass normal authentication and backend authorization.

## Acceptance gates

1. Laravel unit/feature regression + dedicated Phase 5 acceptance.
2. PostgreSQL 17 + PostGIS complete migration chain and Phase 5 concurrency/security acceptance.
3. Flutter analyze + full tests + Phase 5 routing/state tests.
4. UAT endpoint compile-time verification + release APK artifact.
5. Supabase UAT migration/security verification after PostgreSQL CI is green.
6. Render UAT integration/deploy/runtime verification.
7. Real Android device acceptance by the product owner.

No phase is marked CLOSED until these gates are evidenced and the product owner explicitly accepts the Android candidate.
