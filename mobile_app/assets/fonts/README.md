# Bundled Arabic font assets

Phase 1 bundles Noto Sans Arabic for deterministic Arabic/RTL rendering in UAT builds.

Source repository: `notofonts/noto-fonts`
Pinned source commit: `ffebf8c1ee449e544955a7e813c54f9b73848eac`
Family: Noto Sans Arabic
Bundled weights: 400, 500, 600, 700
License file: `OFL.txt` in this directory.

The Phase 1 CI verifies these files are present before Flutter analysis, tests, and APK build. The application must not depend on downloading fonts at runtime.
