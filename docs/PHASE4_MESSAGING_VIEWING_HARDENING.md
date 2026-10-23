# Phase 4 — Messaging + Viewing Journey Hardening

Status: CLOSED / ACCEPTED — automated gates, Supabase UAT schema/security verification, Render UAT deployment, and real-device Android acceptance are COMPLETE.

Branch: `phase4/messaging-viewing-hardening`
Tracker: #16 — closed as completed
PR: #17 -> `phase1/ux-product-foundation` — merged
UAT integration PR: #18 -> `audit/system-stabilization` — merged

## Product boundary

Phase 4 hardens the existing single messaging/viewing implementation. It does not introduce a second chat system, payments, matching/property requests, rental contracts, valuation, legal-library expansion, or Production deployment.

Canonical journey:

`published property -> contact/open property thread -> message -> request viewing -> confirm/reschedule/reject/cancel -> viewing -> complete`

## Messaging contract

- One conversation key per property + participant pair; concurrent opens reuse the same thread.
- Only thread participants can read or send normal private messages.
- Support may open private content only through an active reported-conversation workflow with the dedicated permission; access is audited.
- Message send accepts an optional `client_message_id` for retry-safe delivery.
- Repeating the same key/body returns the existing logical message without a second notification/audit send event.
- Reusing the same key with a different body is a conflict.
- Empty-after-trim messages are rejected server-side.
- Conversation history loads the newest 100 messages first and uses `before_id` to page older history without dropping the newest messages.
- Inbox/read state remains server-authoritative.
- If a listing becomes unpublished, new contact/viewing entry is blocked while the existing participant conversation/history remains available with an explicit unavailable-listing UI state.

Database change:
- `private_messages.client_message_id` nullable;
- unique `(thread_id, sender_user_id, client_message_id)`.

Supabase UAT verification confirms this migration is recorded and the expected column/index are present with RLS enabled and no direct `PUBLIC`/`anon`/`authenticated` table grants.

## Viewing state machine

Initial request:

`requester proposal -> requested -> advertiser confirm | advertiser reject | either allowed party cancel`

Requester reschedule:

`requested|confirmed -> requester proposes replacement -> requested -> advertiser confirm | advertiser reject | either allowed party cancel`

Advertiser reschedule:

`requested|confirmed -> advertiser proposes replacement -> requested -> requester explicitly accepts | requester reschedules again | either allowed party cancel`

The advertiser cannot self-confirm or reject its own replacement proposal while requester acceptance is pending; cancellation remains available if the advertiser needs to terminate the booking.

For an unassigned development-unit viewing, if an authorized development manager proposes a replacement time and the requester accepts it, that proposing manager becomes the booking host.

Completion:

`confirmed + scheduled end reached -> authorized host/manager completes -> completed`

Terminal states (`completed`, `declined`, `cancelled`) cannot be reopened by normal confirm/reschedule/cancel/decline actions.

## Concurrency / authority

- Sensitive booking transitions run in database transactions with row locks.
- PostgreSQL advisory transaction locks serialize conflicting target/requester/host schedule decisions.
- Active overlapping duplicate requests are checked inside the protected creation transaction.
- Confirm checks target, requester, and host confirmed-overlap conflicts server-side.
- Backend state/authorization is authoritative; Flutter button visibility is convenience only.
- Conversation creation and idempotent message send are protected against concurrent duplicate creation on PostgreSQL.
- Active conversation complaint creation is serialized per reporter/thread; complaint resolution uses a locked transaction.

## Notifications and app links

Booking notifications carry `booking_id` and `message_thread_id` when available.

Flutter behavior:
- viewing lifecycle notifications prefer the exact booking destination `/bookings?booking={id}` and prioritize/highlight that booking, even when the booking also has a message thread;
- message-received notifications open the exact message thread;
- other thread notifications without a booking-specific lifecycle target open the thread;
- owned app links support property, message-thread, and viewing-booking targets;
- all private targets still pass the normal authentication/authorization gate.

Owned links:
- `realestate://app/properties/{id}`
- `realestate://app/messages/{threadId}`
- `realestate://app/bookings/{bookingId}`

## Acceptance coverage

Dedicated Laravel acceptance covers:
- conversation reuse;
- participant privacy / IDOR blocking;
- retry-safe message delivery and conflicting-key rejection;
- newest-first bounded history + older pagination without overlap;
- unpublished listing blocks new entry while existing thread remains usable;
- advertiser-reschedule requester-acceptance semantics;
- advertiser cannot reject its own pending reschedule proposal;
- unassigned development reschedule acceptance assigns the proposing manager as host;
- immutable terminal viewing states.

Dedicated Flutter coverage includes:
- property availability + conversation pagination parsing;
- idempotency client message key parsing;
- exact booking/thread notification payload parsing;
- exact notification destination priority for viewing vs message events;
- advertiser-reschedule requester acceptance model state;
- role-aware pending-reschedule Arabic labels;
- completion eligibility after confirmed viewing end;
- message-thread and viewing-booking app links.

Canonical CI: `.github/workflows/phase4-messaging-viewing-ci.yml`

## Final automated evidence

Final documented CI head: `1513399f5c0bb6a8d916c5515cba095389c3c2df`

Phase 4 Messaging Viewing CI run #50 / `34276623699`: SUCCESS.

Successful gates:
1. full Laravel regression;
2. explicit Phase 4 Laravel acceptance;
3. complete migration chain on PostgreSQL 17 + PostGIS;
4. PostgreSQL security/schema regression;
5. explicit Phase 4 acceptance on PostgreSQL;
6. `flutter analyze`;
7. full Flutter tests;
8. compile-time UAT endpoint test;
9. release UAT APK build;
10. APK artifact upload.

Final UAT APK artifact:
- name: `real-estate-phase4-uat-apk-50`;
- size: 44,257,230 bytes;
- digest: `sha256:6a1903236fff5abc966fdb4b4d452b2b022fe22db3f28f79add808438a0af665`;
- expires: 2026-09-22.

The earlier runner failures occurred before any workflow steps while the repository was private. After the product owner changed repository visibility to public, hosted runners executed normally. The first real run exposed one stale source-location assertion in `uat_navigation_integrity_test.dart`; notification routing had intentionally moved into `notification_destination.dart`. The test was corrected to assert the extracted routing contract, without weakening product behavior. Final run #50 passed all gates.

## Supabase UAT evidence

Phase 4 schema/security verification is complete:
- migration `2026_09_08_010000_harden_phase4_messaging_viewings` is recorded in Laravel migration history;
- `private_messages.client_message_id` is nullable `varchar(100)`;
- unique `(thread_id, sender_user_id, client_message_id)` index is present;
- RLS remains enabled;
- no direct `PUBLIC` / `anon` / `authenticated` table grants were found;
- Security Advisor reports only intentional deny-all `rls_enabled_no_policy` INFO;
- Performance Advisor reports existing `unused_index` INFO only.

During the first Render UAT rollout, Laravel startup failed because `property_favorites` already existed but its Laravel migration-history row was missing. The live table was verified to match `2026_09_08_010000_create_property_favorites_table` exactly: columns, PK, cascading FKs, unique key, supporting index, RLS, and deny-all direct grants. Only the missing Laravel `migrations` bookkeeping row was inserted (batch 5); no table/data DDL was reapplied and no user data was modified. The retry then reported `Nothing to migrate`.

## Render UAT evidence

UAT integration PR #18 was merged into `audit/system-stabilization` only.

UAT merge commit:
- `dd9e06d2c613a5322bb9ab34e2e1f869c2d924de`

Render deployment:
- service: `real-estate-uat-api`;
- deploy: `dep-dag7gkmk1f9s738b0tb0`;
- commit: `dd9e06d2c613a5322bb9ab34e2e1f869c2d924de`;
- status: `live`;
- finished: 2026-09-08T21:06:14Z.

Runtime evidence from the new instance:
- Cloud UAT environment check passed for HTTPS, PostgreSQL/PostGIS, Supabase Storage, and UAT guards;
- Laravel reported `Nothing to migrate` after bookkeeping reconciliation;
- Render `/api/health` checks returned HTTP 200 repeatedly during rollout;
- no error-level Render logs were recorded from the successful retry start through post-live verification.

A direct external health request from the execution container could not resolve DNS, so it is not counted as runtime evidence. Render's own health checks and live deployment state are the authoritative runtime evidence recorded here.

## Real-device acceptance

On 2026-09-09, the product owner explicitly accepted the Phase 4 Android candidate after device testing. This closes the final Phase 4 product acceptance gate.

## Closure

Phase 4 is CLOSED / ACCEPTED.

The previously discussed follow-on work — in-app agreement/rental contracts, valuation/price indicators, Real-estate Guide/legal documents, and Production/launch readiness — is preserved for future work but explicitly deferred. It is not the next automatic implementation sequence. The product owner has other priorities to complete first, and the next work package must be defined from those priorities.

## Merge/deploy boundary

- No merge to `main` is authorized by Phase 4 acceptance.
- PR #17 is merged only into the integration branch `phase1/ux-product-foundation`.
- PR #18 is merged only into the UAT runtime branch `audit/system-stabilization`.
- No Production deployment is part of Phase 4.
- Render UAT is verified running the Phase 1–4 UAT integration commit; this does not imply Production readiness.
