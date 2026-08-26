# Real Estate UAT Backend — Render/Supabase

This repository bundle was built directly from the accepted local `CLOUD_READINESS V1.0` backend source supplied by the project owner.

It is intended for a private GitHub repository and remote Docker build on Render. It contains no `.env` files, database dumps, local storage data, APKs, private keys, or deployment credentials.

Deployment order:
1. Configure Supabase UAT (PostGIS + private Storage bucket).
2. Push this repository content to the private GitHub repository.
3. Create/sync the Render Blueprint from `render.yaml`.
4. Enter the `sync: false` values in Render Dashboard only.
5. Deploy and verify `/api/health`.

See `docs/` for the exact checklist.
