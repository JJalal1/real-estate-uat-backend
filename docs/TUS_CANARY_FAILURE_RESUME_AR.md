# Aqer UAT: signed TUS canary diagnostic
- On 23 October 2026 the optional private TUS startup canary failed: signed POST did not return 201 and cleanup also errored.
- Recovery deploy dep-dbdsjct9fdbs738ha3r0 is LIVE; the startup probe is OFF again.
- Root hypothesis from the official Supabase signed Uppy example: signed TUS creation requires /storage/v1/upload/resumable/sign plus apikey (public publishable key) and x-signature. The previous test used the unsigned /resumable endpoint without apikey.
- Draft PR #118 changes the endpoint and header and preserves the original failure, logging response status only.
- Draft PR #115 aligns Flutter, Laravel ticket responses and tests with the signed endpoint; it remains isolated and OFF.
- No successful real signed TUS test has been recorded. No schema migration, backup restore, or production change was performed.
- Next: full CI, explicitly safe UAT canary with ephemeral test object, inspect response code and confirm cleanup; reset probe OFF. Do not apply schema migration before verified restorable backup.
