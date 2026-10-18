# Broker experience — candidate for UAT

Current feature branch: `work/broker-experience-v1`. Purchased design foundation: `c2c7769f1114de434d10866a1032a84c086c1d47`. Scope is the attached Arabic broker UX specification; no production migration or merge into protected baselines is included.

Verified owner, broker and office accounts keep the existing identity, review, messaging, viewing, support and financial authorization systems. Their mobile workspace has Home, Properties, Customers, Activity and Account tabs, using the purchased eBroker components and assets. Public discovery remains available without login.

## Transaction outcomes

The advertiser records an external sale/rental result against an existing property conversation. The linked customer must affirm it. Until affirmation, it contributes no completion, rating eligibility or new receivable. A denial creates an existing support ticket and shared task. A staff member must claim that task using the existing permissions and team scope. Review may cancel the claim or request customer confirmation again; staff cannot invent customer affirmation. Cancellation pauses the listing, leaving normal approved-listing availability confirmation to the advertiser.

The immutable Sai version stored on the conversation remains the calculation source. Confirmation freezes financial terms linked to the outcome rather than creating an agreement. Existing receivable, proof review, hold, ledger and settlement code is reused. Historical contacts without accepted Sai terms do not acquire a retroactive fee. Property-price transfer and broker payouts are absent from this journey. New agreement and rental-contract creation defaults to disabled; existing history and settlements remain accessible. Compatibility tests explicitly enable the legacy creation flag within their disposable test scopes.

## Availability and activity

Sales require confirmation after 14 days; rentals after 7 days. Essential reminders are grouped per advertiser across batches. Exactly two days after notification, an unconfirmed listing is temporarily hidden. Reconfirmation updates only availability; it cannot bypass review, ownership, duplicate checks or financial restrictions. Closing an external-platform listing creates no outcome or rating eligibility. Bulk changes validate every owner and apply atomically, up to 100 IDs per request.

The command `broker:refresh-availability` is scheduled hourly. A bounded, throttled API sweep is a fallback for UAT services without a continuously running scheduler. Public queries also enforce an expired notification grace immediately. Views are recorded only on actual detail-screen entry, not card prefetches, once per user/anonymous device per day; the anonymous random key is separate from legacy local ownership credentials. Saves, conversations and viewings come from the canonical entities. Customer completion is server-derived from confirmed outcomes.

## Public profile and ranking

Only active, phone-verified professionals with reviewed, approved identities enter the directory. Verification photos/documents, email and telephone are not exposed. Public photos require a separate explicit upload, through the existing server-side storage abstraction. Private identity evidence is never reused. Work areas and specialties come from approved profile details. Contact and viewing start from an active selected property.

Ordering is independent of displayed stars: 50% rating quality, 35% recent confirmed deals and 15% recent healthy listings. Quality is `(average / 5) * (count / (count + 5))`. Deal credit uses the last 90 days: settled/no-due outcomes count 1, unsettled outcomes count 0.5, capped at 20 credits. Activity uses listing confirmations/publications in the last 30 days, capped at 20; unavailable or financially hidden listings contribute nothing. Local approved governorate matches precede broader results; tied scores use rating count and user ID. Stars remain the actual visible confirmed-customer average. The current Sana'a discovery default uses Amanat al-Asimah; users can change the governorate or select all.

## Verification and release

`Broker Experience CI` runs the original Laravel suite, disposable PostgreSQL/PostGIS migration and access checks, Flutter analysis, original and new widget/navigation regression, rendered previews and a release UAT APK. Native Android code, dependency declarations and original pinned build dependency checks remain intact. Compilation targets the existing Frankfurt UAT API. Deploy only the green feature commit to the existing UAT runtime and apply Laravel migrations there; do not apply anonymous/client database grants. Commit evidence and APK SHA-256 accompany the build artifact. Feature PR merging still requires the repository's review and product-owner approval policy.


## Broker conveniences

- Dashboard unread/follow-up/viewing shortcuts retain the requested filter/tab. Read markers are authoritative on the server.
- The canonical listing editor recovers text, public listing photos and its current step locally per signed-in account and original editor listing ID. Android recovery lives in app-private `no_backup`; no token, identity/selfie or ownership-proof file is copied. An existing saved draft ID is resolved before another write to avoid creating a duplicate. A successful explicit server save removes local recovery. Public listing media and private evidence uploads remain explicit; preview never submits.
- Customer notes and reminders reuse the canonical property conversation. GET/PATCH `/broker/customers/{thread}/followup` authorize the current verified listing owner/participant. Notes never enter customer messages, public profiles, notification bodies or audit metadata. The due processor locks rows and creates one owner-only notification per scheduled date; rescheduling/completing marks the old notice read. Scheduled commands and bounded traffic refresh reuse existing notification infrastructure. This UAT uses in-app reminders; a sleeping free runtime advances due reminders when relevant traffic resumes.
- Quick replies insert editable composer text. Only the existing explicit Send button sends a retry-safe message; no viewing or transaction is auto-confirmed.
- `starts_from`/`starts_before` on existing booking lists scope a bounded UTC date window while preserving actor permissions. The phone supplies its local day boundaries, renders today chronologically, and opens the canonical conversation or a currently public property's map coordinates.
- Operational cards expose a primary authorized action and a menu retaining all other actions. Backend review, financial, ownership and two-party-confirmation rules remain unchanged.
