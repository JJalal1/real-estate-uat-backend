# UAT Runbook — REAL ESTATE

## Goal

UAT success means the same shared backend/database/storage behavior works across multiple devices and roles. HTTP 200 alone is not sufficient acceptance.

## 1. Preflight before a UAT cycle

- Confirm Git HEAD / PR commit under test.
- Confirm required GitHub Actions checks are green.
- Confirm Render UAT service is live.
- Confirm `/api/health` reports application/database/PostGIS healthy.
- Confirm the intended UAT API base is compiled into the APK.
- Confirm no Production resources are in use.
- Use only UAT test accounts/data.

## 2. Mobile build acceptance

For Flutter changes:

1. Wait for `Build UAT Android APK` to succeed.
2. Use the artifact from the exact accepted commit/run.
3. Verify BUILD_INFO/SHA evidence when available.
4. Install/update the APK on the UAT devices.
5. Do not use an artifact from an older green run if it lacks the current change.

## 3. Multi-device listing review acceptance

Example:

### Phone A — publisher

- log in
- create listing
- fill required data/media/location/evidence
- submit
- verify status is review/pending rather than immediately public when review is required

### Phone B — support

- see the unassigned review item
- claim it
- verify another support account no longer sees it as unassigned
- return with a reason

### Phone A

- see returned status and reason
- edit
- resubmit

### Phone B

- approve

### Phone C — visitor/other user

- verify the listing is now public

## 4. Support shared-queue acceptance

Use at least two eligible support accounts:

- both initially see the same unassigned item
- one claims it
- claimant sees it under own tasks
- the other loses it from the unassigned queue
- if both attempt claim near-simultaneously, only one backend claim succeeds

## 5. Professional verification acceptance

Test separately:

- owner
- broker
- office

Validate:

- correct fields/documents
- selfie camera-only behavior
- submission pending state
- duplicate-submit prevention while pending
- support claim/review
- requested-additional-document loop if supported
- approved state unlocks only allowed professional capabilities

## 6. Property Requests acceptance — when Phase 2 lands

Use requester + verified broker/office:

- requester creates persistent property request
- request appears in own list
- eligible broker/office sees suitable active request
- ineligible/basic/owner account cannot use researcher-request capability if backend rules deny it
- broker/office proposes only an allowed approved/published property
- duplicate suggestion is rejected or handled by defined rules
- requester receives notification
- notification opens the actual request/suggestion/property context
- requester can continue to conversation/viewing according to authorization

## 7. Favorites acceptance — when implemented

- save property on Phone A
- sign in same user on Phone B
- favorite appears server-side
- remove/save state remains consistent
- if property becomes unavailable, favorite remains understandable with unavailable state and invalid actions blocked

## 8. Viewing/booking acceptance

- start from property details
- requester proposes time
- advertiser receives notification
- related conversation opens/exists
- advertiser confirm/reschedule/reject behavior propagates
- both parties see booking state
- history/reference integrity is preserved

## 9. Rental contract acceptance — when implemented

- start from real property/eligible party workflow
- create draft
- other party can review/confirm according to rules
- both-party confirmation produces correct agreed/active wording
- no claim of government notarization
- unauthorized users cannot read/update the contract

## 10. Performance acceptance

Separate cold-start from warm behavior.

Record:

- first request after Render sleep
- warm `/api/health`
- representative list endpoint
- admin/support dashboard load
- approve/reject/save actions

If warm requests remain slow, inspect backend/DB/network rather than blaming Flutter navigation.

## 11. Failure handling

When a UAT case fails:

1. Reproduce.
2. Identify client vs API vs DB vs network vs cloud deployment.
3. Capture exact commit/run/log evidence.
4. Make the smallest focused fix on a branch.
5. Add/update a regression test when practical.
6. Re-run CI.
7. Repeat only the affected UAT path plus required regression checks.

## 12. Release boundary

Passing UAT does not mean Production release is approved. Production database, Play Store, real payments, real customer identity documents, and final production infrastructure require a separate explicit phase and approval.
