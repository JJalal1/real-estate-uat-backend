# AI Task Template — REAL ESTATE

Use this template when assigning a substantial coding task to ChatGPT/Codex.

## Goal

Describe the product outcome, not just the file change.

## Required reading

Before editing:

- `AGENTS.md`
- `docs/AI_PROJECT_STATE.md`
- `docs/ARCHITECTURE.md`
- `docs/BUSINESS_RULES.md`
- `docs/WORKFLOWS.md`
- `docs/SECURITY.md`
- current implementation files for the feature

## Constraints

- UAT only unless explicitly stated otherwise.
- Preserve architecture/roles/permissions/API compatibility unless the task requires a deliberate change.
- Backend authorization is authoritative.
- No secrets in source, chat, logs, PRs, or artifacts.
- Do not add paid product behavior.
- Do not add broker hierarchy or regional exclusivity.
- Reuse existing entities/workflows where practical.

## Implementation expectations

1. Inspect current code and tests.
2. State the smallest coherent implementation plan.
3. Create/update backend persistence and authorization if required.
4. Create/update Flutter models/repositories/UI/navigation if required.
5. Add tests for permissions, state transitions, persistence, and important UI contracts.
6. Run targeted tests, then required regression checks.
7. Run `git diff --check`.
8. Review the diff for unrelated changes and secrets.
9. Update `docs/AI_PROJECT_STATE.md` or decision docs if accepted behavior changes.
10. Open a Pull Request; do not merge without product-owner approval.

## Acceptance criteria

List explicit user-visible and backend/security behaviors here.

## UAT scenario

Describe the multi-device/role scenario that proves the feature works end to end.

## Do not do

List scope exclusions here. Common examples:

- no Production
- no Play Store release
- no real payments
- no architecture rewrite
- no unrelated refactor

## Final report expected from agent

- files changed
- migrations added
- API changes
- tests run and results
- known limitations
- manual UAT steps
- security/authorization notes
- CI/PR status
