# Security — REAL ESTATE UAT

## Security posture

This repository is UAT/staging, but security rules should be close to Production quality because the application handles identity, ownership evidence, location, conversations, roles, and private documents.

## 1. Secrets

Never commit or expose:

- `.env`
- Laravel `APP_KEY`
- database passwords
- credential-bearing DB URLs
- Supabase server/service keys
- UAT OTP code
- WhatsApp/API secrets
- private keys
- Android signing secrets / keystore passwords

GitHub/ChatGPT/CI may verify environment variable names and presence, but secret values should remain masked and outside chat/artifacts.

## 2. UAT OTP

- Test OTP is allowed only in staging/UAT.
- It must remain allowlist-based.
- Production must reject/disable the UAT test-OTP path.
- Any auth refactor must include tests proving the environment guard.

## 3. Authorization

Laravel/backend is the final authority for all sensitive actions.

Never rely on:

- hidden buttons
- disabled Flutter controls
- client-provided role names
- client-provided ownership claims

Check authenticated user, permissions, account-verification state, resource relationship, and workflow status server-side.

## 4. IDOR / object access

For every endpoint that accepts an entity ID, verify the requesting user may access that exact entity.

High-risk examples:

- verification applications/documents
- property ownership documents
- unpublished listings
- support tasks
- private conversations
- viewing requests/bookings
- favorites tied to a user
- future property requests/suggestions
- future rental contracts

Do not assume a UUID/large numeric ID is authorization.

## 5. Private storage

Identity/selfie/property proof/private office documents stay private.

Use server-authorized retrieval/signed access patterns where needed. Do not make a private bucket public to simplify UAT.

Public listing media may use a public-safe path only when the product intentionally classifies it as public.

## 6. Support access

Support must not have unrestricted private-message access by default.

Sensitive conversation review should require:

- an explicit permission
- a valid reported/complaint case or allowed context
- audit logging

Manager/platform-owner privileges must still be explicit in backend policy/permission logic.

## 7. Auditability

High-value actions should be auditable when the current system supports it, including:

- role/permission changes
- verification decisions
- listing review decisions
- support assignment/reassignment
- private-conversation review access
- high-risk moderation actions
- future contract state changes where appropriate

Avoid logging secret values or full sensitive documents.

## 8. Validation

Validate server-side:

- enum/status transitions
- ownership/resource relationship
- upload type/size/path rules
- numeric ranges
- geographic fields where required
- duplicate submissions/suggestions
- concurrency-sensitive claim actions

Do not trust Flutter validation as the only validation.

## 9. Concurrency

Shared support queue claim must be race-safe. Future suggestion/matching and contract-confirmation flows should also protect uniqueness/state transitions at the database/backend layer where races are possible.

## 10. Personal data minimization

Do not expose unnecessary requester contact information to brokers/offices in Researcher Requests. Prefer workflow-based contact through platform notifications/conversations after an appropriate suggestion/interaction.

## 11. Legal content

Guide/templates are informational. Avoid claiming a document is officially notarized/government-certified without a real verified integration.

## 12. AI agent rules

AI agents must:

- never request secret values in chat
- never paste secrets into source, PRs, issues, logs, or generated Result artifacts
- inspect diffs for accidental secret inclusion before proposing merge
- use UAT resources only unless explicitly authorized otherwise
- not delete cloud services/databases or create paid resources without explicit product-owner approval
