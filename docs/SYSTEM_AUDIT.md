# SYSTEM AUDIT & STABILIZATION — Phase 0

Status: ACTIVE
Branch: `audit/system-stabilization`
Scope: current accepted system only. New Phase 2 feature work is frozen until this audit is complete.

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

Only after these conditions are satisfied should new Phase 2 feature implementation resume.
