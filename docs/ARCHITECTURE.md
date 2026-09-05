# Architecture — REAL ESTATE UAT

## System overview

REAL ESTATE is a multi-device UAT real-estate platform. The same backend/database/storage must serve several phones simultaneously so that user actions are visible across roles.

### Mobile

- Flutter Android application under `mobile_app/`.
- Uses compile-time UAT configuration in GitHub Actions.
- Current UAT API base is injected with `--dart-define`.
- Mobile UI may hide actions, but it is never the authority for permissions.

### Backend

- Laravel API under `backend-api-runtime/`.
- Owns authorization, workflow state transitions, persistence, audit-relevant decisions, and secure storage access.
- Backend changes should be tested and deployed independently from APK builds unless the mobile contract changes.

### Database

- PostgreSQL for application data.
- PostGIS enabled for geospatial/region/property-location behavior.
- Existing migrations are part of the source of truth. New schema work must use migrations and be UAT-safe.

### Storage

- Supabase Storage.
- Sensitive identity/property documents remain private.
- Flutter must never contain Supabase server/service credentials.
- Laravel performs privileged server-side storage operations where needed.

### Hosting

- Render hosts the Laravel UAT service.
- `render.yaml` defines the current Docker-based UAT service and environment-variable names.
- Do not infer a secret value from configuration; only names/non-sensitive settings belong in source.

### Source control and CI

- GitHub repository: `JJalal1/real-estate-uat-backend`.
- Main branch: `main`.
- Flutter workflow: `.github/workflows/build-uat-apk.yml`.
- Workflow currently performs accepted-source hash checks, dependency resolution, static analysis, tests, live health verification, release APK build, and artifact upload.

## Authority boundaries

### Laravel/backend owns

- role/permission authorization
- account-verification decisions
- support-task claim ownership
- listing review state transitions
- property-request persistence and authorization (when implemented)
- favorites persistence (when implemented)
- viewing/booking state
- contract state (when implemented)
- notifications and references/deep-link targets
- server-side validation and audit events

### Flutter owns

- presentation
- navigation
- input collection
- loading/error states
- client-side convenience validation
- rendering server-authorized capabilities

Flutter must not create a second permission model that can diverge from Laravel.

## Important domains

### Identity and professional verification

Basic users can browse/search/buy. Professional verification can represent:

- owner
- broker
- real-estate office

Support/admin roles are operational permissions and must not be confused with those professional profile types.

### Listings

Expected high-level lifecycle:

`draft/input -> submit -> support/review queue -> claimed review -> approve / return for correction / reject -> published when approved`

The exact enum/state names must be taken from current code before editing.

### Support work

Support work uses a shared queue and explicit claim behavior. Concurrency must be protected in backend logic. Support manager/platform owner may have reassignment/escalation abilities according to permissions.

### Conversations and viewing

A viewing request must be related to a specific property. The intended product path is:

`property -> viewing request -> notification -> conversation -> confirm/reschedule/reject -> booking visible to both parties`

Reuse existing entities where possible rather than adding a competing conversation/booking system.

### Services hub

Current free-services hub is backend-capability driven. `/api/services/hub` exposes the server decision used by Flutter. Paid features are disabled in the active user journey.

## Deployment flows

### Backend-only change

`branch -> tests -> PR -> merge -> Render deploy -> health/API smoke -> UAT acceptance`

No APK is required solely for server-side changes when the mobile contract remains compatible.

### Flutter/mobile change

`branch -> tests -> PR -> merge -> GitHub Actions -> green APK artifact -> install/update UAT APK -> multi-device acceptance`

### Database migration

`migration code -> automated tests -> PR -> UAT deploy/migration -> schema/API verification -> manual acceptance`

Never apply a Production migration as part of current UAT work.

## Performance diagnostics

If UI navigation is fast but data actions are slow, classify the problem as data/network/backend latency rather than Flutter animation jank.

Measure before optimizing:

- Render cold-start effect
- Render ↔ Supabase region latency
- endpoint timing
- SQL query count
- N+1 behavior
- repeated counts/aggregates
- eager loading
- indexes/joins
- sequential requests
- audit-log overhead
- transaction duration

Do not add caching as a reflex before diagnosis.
