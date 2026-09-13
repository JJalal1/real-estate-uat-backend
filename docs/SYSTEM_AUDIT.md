# SYSTEM AUDIT & STABILIZATION — Phase 0

Status: ACTIVE — automated/server-side gates passed; visual device acceptance remains outstanding
Branch: `audit/system-stabilization`
Scope: current accepted system only. New Phase 2 feature work is frozen until this audit is complete.

## Audit execution record

Audit baseline: Git HEAD `5b2c226aca467fc8ec392782d6e2a1a0d7271bb6` plus the audit branch documentation commit `06bfad322f49a8be9200ede474d6481cfa41e4d3`.

Repository inventory at the start of execution:

- 123 Flutter/Dart source files, 16 Flutter repositories, and 30 Flutter tests.
- 163 declared Laravel API routes, 17 API controllers, and 22 backend test classes.
- 29 Laravel migrations in the accepted baseline; this audit adds one schema-hardening migration.
- One GitHub Actions workflow, previously scoped only to Flutter changes pushed to `main`.

### Flutter route and surface inventory

| Surface | Entry point | Access | Audit disposition |
|---|---|---|---|
| Role-aware application shell | `/` | Public shell; authenticated role variants | Current; regular, support agent, support manager, and platform administration tabs inventoried |
| Login/register | `/auth` | Public | Current; WhatsApp and legacy credential flows retained |
| Phone verification | `/verify-phone` | Auth flow | Current |
| Profile completion | `/complete-profile` | Authenticated, inactive allowed | Current |
| Unified account verification | `/account-verification` | Active account | Current; notification destination repaired |
| Password recovery | `/forgot-password` | Public | Current |
| Account/profile | `/profile` and shell tab | Authenticated, inactive allowed | Current |
| Access control | `/admin/access` | Backend permission enforced | Current |
| Admin dashboard/settings/audit | `/admin/dashboard`, `/admin/settings`, `/admin/audit-log` | Backend permission enforced | Current |
| Listing review | `/admin/listing-review` | Listing moderation permission | Current; shared-task assignment remains authoritative |
| Legacy broker KYC administration | `/broker/account-verification`, `/admin/broker-account-verifications` | Authenticated/permissioned | Compatibility-only; unified KYC is the current public workflow |
| Unified KYC administration | `/admin/account-verifications` | Account verification permission | Current; ownership bypass fixed for approve/more-info/reject |
| Region administration | `/admin/regions` | Region management permission | Current |
| Messages and conversation | `/messages`, `/messages/:id` | Active account/participant | Current; invalid IDs now fail safely |
| Notifications | `/notifications` | Active account | Current; current entity types now open their real destinations |
| Conversation reports | `/admin/message-reports` | Support/private-review permissions | Current; private content remains gated and audited |
| Viewing bookings | `/bookings` | Active account | Current |
| Free services hub | `/services` | Active account | Current; planned services remain explicitly marked unavailable and were not implemented |
| User support center | `/support?case=:id` | Active account/owner | Current; notification deep link opens the referenced case |
| Support administration | `/admin/support?kind=:kind&case=:id` | Support permission | Current |
| Shared support workspace | `/support/workspace` plus role shell tabs | Support roles | Current |
| Support users/worklog | `/support/users`, `/support/worklog` | Support permissions | Current |
| Property detail | `/properties/:id` | Public published listing or authorized owner/reviewer | Current; invalid IDs now fail safely |
| Add property | `/add-property` | Verified publishing profile | Current |
| My listings | `/my-listings` | Active account | Current |
| Map, listing community, location picker, dialogs | Embedded from shell/property/workflows | Contextual | Current; not separate router destinations |
| Fake local chat | Former `/chats/:id` | None | Removed: duplicated the real messaging system with hard-coded data and inert buttons |
| Developments/projects UI source | No current route or shell entry | Unreachable | Intentionally excluded by accepted product decision; not restored |
| Retired broker-region verification UI | No current shell entry | Unreachable | Historical compatibility only; not restored |

All current top-level screens use RTL directionality directly or inherit it from the application theme/shell. Reachable async data screens were source-reviewed for loading, empty, error/retry, and refresh handling. Real rendered-device verification remains the explicit visual acceptance gate.

### Verified defects and fixes

| Layer | Defect | Severity | Resolution |
|---|---|---:|---|
| Authorization | A support agent could call legacy unified-KYC `more-info` and `reject` actions without owning the shared task; only `approve` was protected | High | Apply ownership middleware to all three decisions and add cross-agent regression coverage |
| Navigation | `int.parse` on message/property path parameters could crash malformed deep links; unknown routes had no product error surface | Medium | Use positive `int.tryParse`, add Arabic route-error UI, and add a router error builder |
| Messaging UI | `/chats/:id` exposed a hard-coded duplicate chat with inert buttons | High | Remove the route, import, and obsolete source file; retain the API-backed messaging flow only |
| Notifications | Only message notifications navigated; KYC, support, task, booking, property, and service notifications silently stopped after being marked read | Medium | Add destinations for current entity types, support-case deep linking, and explicit feedback for historical unknown types |
| Report notifications | Closing a conversation report linked the user to an entity type with no client destination | Medium | Emit the related support-case entity, falling back to the thread, and cover it in backend tests |
| Database drift | UAT lacked four latest accepted migrations | Critical | Reconciled through reviewed Git migrations; live UAT now reports nothing pending |
| Supabase security | Application tables in exposed `public` lacked RLS and trigger functions had mutable search paths | High | Applied reviewed PostgreSQL hardening: RLS, direct-grant revocation, pinned search paths, future-table event trigger |
| Database performance | Supabase identified foreign-key columns without supporting indexes | Medium | Added idempotent PostgreSQL indexes; retain unused indexes until workload evidence justifies removal |
| CI | No backend test job, no audit-branch trigger, and backend-only changes did not trigger CI | High | Added PHP 8.4 Laravel tests, PostgreSQL/PostGIS migration/security tests, audit-branch/backend triggers, Flutter regression/build gates |
| Render port binding | Apache ignored Render runtime `PORT` | Critical | Validate `PORT` and rewrite Apache listen/vhost configuration before startup |
| Access-role validation | Intentional empty role list was rejected as missing | Medium | Require key presence while allowing empty array; registered-user invariant remains in service |
| Regression suite drift | Legacy identity/listing tests bypassed accepted verified-publisher/shared-claim rules | Medium | Updated fixtures while preserving product rules |
| UAT connection saturation | Initial 10-worker prefork baseline queued the post-burst health check under a 40-request/concurrency-20 probe | High | Raised bounded UAT prefork ceiling to 12 with session-pool headroom; deterministic probe now requires 40/40 success plus healthy post-load check |
| Persistent-session experiment | Optional persistent PostgreSQL sessions increased idle session retention without being necessary for stability | Medium | Reverted; accepted UAT database connections remain non-persistent |

## 2026-09-07 automated acceptance checkpoint

The automated/server-side portion of Phase 0 is now accepted on the audit branch. The final application-code deployment baseline is commit `3c761f7257a2290f1449f4e9c246e659595bea8c` (`revert: keep PostgreSQL sessions non-persistent`). Documentation-only commits may follow it without changing runtime code.

### Runtime acceptance log

| Check | State | Evidence / remaining gate |
|---|---|---|
| Local/static inventory and secret-pattern review | Passed | No committed credentials found; server-only sensitive configuration remains outside source |
| Supabase UAT identity/version | Passed | Connected UAT is healthy on PostgreSQL 17.6 with PostGIS |
| Supabase schema match | Passed | Reviewed accepted migrations applied; Render reports `Nothing to migrate.` |
| Supabase direct Data API boundary | Passed | All application/public tables have RLS and `anon`/`authenticated` have zero direct table grants |
| Supabase security advisors | Passed with expected INFO | Remaining `rls_enabled_no_policy` INFO is deliberate deny-all direct Data API posture; Laravel is authoritative data access |
| Supabase performance advisors | Passed with informational follow-up | Remaining findings are unused-index INFO only; no index removal without workload evidence |
| PostgreSQL/PostGIS regression | Passed | Disposable PostgreSQL migration chain, schema/access audit, and spatial overlap regression are green in CI |
| Laravel tests | Passed | Final-code CI run has backend suite green |
| Flutter static analysis/tests | Passed | Flutter analysis, cloud-readiness, compiled-environment guard, and full test suite are green on accepted audit state |
| Release UAT APK | Passed on accepted audit state | Green CI builds and uploads a release UAT artifact; final-code run is the canonical artifact once complete |
| Render UAT deployment | Passed | Deploy `dep-daf0v7gn74is73frnce0` is live at runtime commit `3c761f...`; cloud readiness passed and migrations are current |
| Render health/log review | Passed | Repeated `/api/health` HTTP 200 after cutover; no app `error`/`critical` entries after final deploy became live |
| Connection state after persistent-session rollback | Passed | Supabase activity normalized; no application-owned persistent idle-session pool remains; infrastructure-managed Supavisor/PostgREST sessions are expected |
| Concurrent read-only UAT stability | Passed | 40 nearby-property requests at concurrency 20 completed 40/40 with post-load health green after 12-worker tuning |
| Performance characterization | Passed for UAT stability, not production SLO | Accepted probe recorded multi-second p95 under deliberate burst; direct PostGIS plan uses spatial index, so region/network/round-trip cost remains a likely UAT latency contributor |
| Real APK visual/device end-to-end pass | Outstanding | Requires Computer Use/real emulator-device environment; this is the only remaining Phase 0 DoD gate not executable by the ordinary connector/tool environment |

### Accepted UAT capacity posture

- Apache prefork `MaxRequestWorkers`: 12.
- PostgreSQL application sessions: non-persistent.
- Do not increase worker/session ceilings merely to lower latency; preserve pool headroom and measure first.
- Render UAT is in Oregon while Supabase UAT is in Mumbai. Cross-region placement is a known latency risk; changing regions/resources is a separate infrastructure decision and must not be done without cost/impact review.
- The concurrent CI probe is a regression/stability check, not a production traffic promise or SLA.

## Objective

Audit the complete existing product end-to-end, find and fix broken, empty, placeholder, unreachable, inconsistent, or error-prone areas, and leave the current system stable before new feature phases resume.

## Operating rules

- GitHub is the source of truth.
- Work only through a dedicated branch and PR; do not push directly to `main`.
- Preserve documented business rules and accepted baselines unless a verified defect requires a change.
- Use UAT Render and UAT Supabase only for runtime/database verification and safe UAT fixes.
- Do not modify Production or expose secrets.
- Do not implement Phase 2 feature scope during this stabilization phase.
- Every defect must be traced to the correct layer: Flutter UI/navigation/state, API contract/backend, database, deployment/configuration, or CI.
- Prefer fixing root causes over hiding symptoms.

## Audit tracks

### 1. Product surface inventory

For every Flutter route, screen, dialog, tab, menu action, deep link, and role-specific surface:

- classify as working / broken / empty / placeholder / unreachable / inconsistent;
- verify loading, empty, populated, error, offline/retry, unauthorized, and expired-session states where applicable;
- verify Arabic/RTL layout, overflow, spacing, typography, touch targets, back navigation, keyboard behavior, and small-screen behavior;
- verify every visible action actually has a valid destination and expected result.

### 2. Navigation and state

- inventory router paths and route parameters;
- find dead routes, missing routes, duplicate destinations, invalid arguments, and broken redirects;
- verify authentication and role-based guards;
- verify session restoration and logout/reset behavior.

### 3. Flutter ↔ API contracts

- inventory all network calls and repositories;
- map each call to the Laravel route/controller/request/resource;
- verify request payloads, response parsing, nullability, pagination, validation errors, status codes, and retry/error handling;
- remove or repair stale/unused contracts only after impact review.

### 4. Laravel/backend

- inspect routes, controllers, requests, policies/middleware, models, resources, jobs, storage, and tests;
- verify authentication, authorization, ownership rules, IDOR protection, validation, and sensitive-data handling;
- find routes that can return unexpected shapes/errors or are not represented correctly in Flutter.

### 5. Supabase UAT / PostgreSQL / PostGIS

- inventory schema, migrations, constraints, indexes, relationships, spatial types/indexes, and storage-related assumptions;
- compare schema expectations with Laravel models/migrations;
- inspect slow or unsafe query patterns where evidence exists;
- apply UAT migrations only after review and only when required by a verified fix.

### 6. Render UAT

- verify current service/deploy health;
- inspect logs for crashes, repeated exceptions, timeout/error patterns, and configuration mismatches;
- correlate runtime failures with exact commits/code paths.

### 7. CI and build

- make baseline static analysis/tests/build deterministic;
- distinguish current-system regressions from frozen future-phase work;
- require a clean UAT APK build before closing Phase 0.

### 8. Visual/end-to-end acceptance

When Computer Use is available in Work/Codex on the Windows host:

- launch the real UAT APK/emulator;
- traverse every reachable current-system screen and role flow;
- visually inspect actual rendered states rather than relying only on source review;
- reproduce and trace every visual/runtime defect;
- retest after fixes.

### 9. Security/regression review

- independently review authorization boundaries, private chats/documents, KYC-related data, storage access, tokens/sessions, and role permissions;
- rerun regression coverage after all fixes.

### 10. Documentation closeout

Update project-state/changelog/decisions/runbook documentation to match the verified final system.

## Definition of done

Phase 0 is complete only when:

1. every existing reachable product surface is inventoried;
2. no known current-system page is unintentionally blank, broken, placeholder-only, unreachable, or linked to a dead action;
3. critical loading/empty/error/auth states are handled;
4. Flutter/API/backend/database contracts are reconciled;
5. current-system CI is green;
6. Render UAT is healthy after the audit fixes;
7. Supabase UAT matches the verified application expectations;
8. a release UAT APK is built successfully;
9. visual end-to-end acceptance has been completed when the Computer Use environment is available;
10. security/regression review is complete;
11. documentation reflects the verified state.

Automated/server-side gates 1–8, 10, and 11 are now satisfied to the extent they are verifiable without a rendered device. Gate 9 remains outstanding. Phase 2 stays frozen and no merge to `main` is authorized until the remaining acceptance gate is completed and the product owner explicitly approves the merge.
