# Phase 4 — Messaging + Viewing Journey Hardening

Status: CLOSURE CANDIDATE — automated gates and Supabase UAT schema/security verification COMPLETE; Render UAT runtime verification and real-device acceptance remain.

Branch: `phase4/messaging-viewing-hardening`
Draft PR: #17 -> `phase1/ux-product-foundation`
UAT integration PR: #18 -> `audit/system-stabilization`

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

Supabase UAT verification confirms this migration is already recorded and the expected column/index are present with RLS enabled and no direct `PUBLIC`/`anon`/`authenticated` table grants.

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

Accepted application/test head: `fadac78ad5ce3abb260c5db468ea175d2d9a6a54`

Phase 4 Messaging Viewing CI run #48 / `34275753072`: SUCCESS.

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

Artifact:
- name: `real-estate-phase4-uat-apk-48`;
- size: 44,257,241 bytes;
- digest: `sha256:040118c60d24b83156842ff83d1c6816f4c1b95279cc68f0fa62a1438127bcbc`;
- expires: 2026-09-22.

The first runner-enabled attempt after the repository was changed from private to public exposed one stale source-location assertion in `uat_navigation_integrity_test.dart`: notification routing had intentionally moved into `notification_destination.dart`. The test was corrected to assert the extracted routing contract; no product behavior was weakened. The subsequent final run #48 passed all gates.

## Supabase UAT evidence

Phase 4 schema/security verification is complete:
- migration `harden_phase4_messaging_viewings` is recorded;
- `private_messages.client_message_id` is nullable `varchar(100)`;
- unique `(thread_id, sender_user_id, client_message_id)` index is present;
- RLS remains enabled;
- no direct `PUBLIC` / `anon` / `authenticated` table grants were found;
- Security Advisor reports only intentional deny-all `rls_enabled_no_policy` INFO;
- Performance Advisor reports existing `unused_index` INFO only.

## Remaining closure gates

1. integrate Phase 4 into the UAT runtime branch `audit/system-stabilization`;
2. manually deploy Render UAT because auto-deploy is disabled;
3. verify `/api/health` and the live property-linked messaging/viewing journey on UAT;
4. install/test the Phase 4 APK on a real Android device;
5. explicit product-owner Phase 4 acceptance.

## Merge/deploy boundary

- No merge to `main` is authorized by Phase 4 work.
- PR #17 remains separate from Production and targets only `phase1/ux-product-foundation`.
- PR #18 is the UAT-only integration path to `audit/system-stabilization`.
- No Production deployment is part of Phase 4.
- Successful CI and Supabase verification do not claim Render UAT is running Phase 4 until the runtime is actually integrated, deployed, and verified.
