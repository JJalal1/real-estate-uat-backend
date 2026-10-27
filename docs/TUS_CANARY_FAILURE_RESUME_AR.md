# Aqer UAT: signed TUS canary diagnostic

## Current result — 24 October 2026

PR118 merged at `23ddba16d33e50b45a954d9d5e0d2dfe67737d8a`. Signed `/upload/resumable/sign` + public apikey + file x-signature passed twice on UAT: PATCH6291456, HEAD exact offset, PATCH46; downloaded length6291502 and SHA256 verified, then cleanup. The provider independently logged POST201, HEAD200, both PATCH204 and forged-signature POST400. See `evidence/2026-10-24-tus-live-wire.json`.

Deploys `dep-dbdtcp5g1s2s73b18o80` and `dep-dbdtcrebv0ns73br2ps0` were Live. Resetting the probe OFF deployed `dep-dbdtdcec36kc73813fdg` Live. Current adaptive-image deployment `dep-dbdttugae00c73b0087g` is Live at `6a0475e82b3a12f59cab3eb78ba75ee4e283186b`.

PR115 remains Draft with the migration undeployed and feature OFF. Full UAT backup and independent restore are still absent; do not equate this protocol canary with Flutter/Laravel intent lifecycle or handset acceptance. Read `AQER_11_12_EXECUTIVE_HANDOFF_AR_2026-10-24.md` first.

## Prior failed run (historical, superseded by the result above)

- On 23 October 2026 the optional private TUS startup canary failed: signed POST did not return 201 and cleanup also errored.
- Recovery deploy dep-dbdsjct9fdbs738ha3r0 is LIVE; the startup probe is OFF again.
- Root hypothesis from the official Supabase signed Uppy example: signed TUS creation requires /storage/v1/upload/resumable/sign plus apikey (public publishable key) and x-signature. The previous test used the unsigned /resumable endpoint without apikey.
- Draft PR #118 changes the endpoint and header and preserves the original failure, logging response status only.
- Draft PR #115 aligns Flutter, Laravel ticket responses and tests with the signed endpoint; it remains isolated and OFF.
- No successful real signed TUS test has been recorded. No schema migration, backup restore, or production change was performed.
- Next: full CI, explicitly safe UAT canary with ephemeral test object, inspect response code and confirm cleanup; reset probe OFF. Do not apply schema migration before verified restorable backup.
