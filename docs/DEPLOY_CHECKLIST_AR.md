# Checklist النشر

- [ ] GitHub repository Private.
- [ ] PostGIS enabled in Supabase schema `gis`.
- [ ] Private Storage bucket `real-estate-uat` exists.
- [ ] Render Blueprint reads `render.yaml` from repository root.
- [ ] All `sync: false` variables entered in Render Dashboard.
- [ ] First deploy completes migrations successfully.
- [ ] `GET /api/health` returns HTTP 200 with database and postgis healthy.
- [ ] No deployment secret is stored in GitHub.
