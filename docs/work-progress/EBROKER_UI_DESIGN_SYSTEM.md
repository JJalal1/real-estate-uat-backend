# Arabic real-estate design system

Phase 1 evolves the existing `core/theme` and `core/widgets` contract. Import `core/design/app_design.dart` for the combined presentation API. There is one palette, one typography scale and one set of tokens. No new package, network request, role or product field is introduced.

## Foundations

- Original identity: عقارات حولك, existing green primary, warm neutral page and white surfaces. Semantic success/warning/error/info colors retain their meaning and contrast coverage.
- Locally bundled NotoSansArabic with inherited RTL, explicit Arabic line heights and unrestricted platform text scaling.
- Directional spacing: page gutters 16 / 24; content capped at 840; related items 12 / 16; sections 24 / 32. Use tokens, not repeated screen literals.
- Existing radius hierarchy: controls 12, cards 16, sheets and feedback marks 24, compact status pills. Existing elevation tokens remain available for overlays; avoid shadows around every nested block.
- Every independent action retains at least a 48px target. Content-bearing components grow rather than fix their height.
- Navigation animation respects the platform reduced-motion preference. Navigation mode, order, number of tabs, and selection callbacks are unchanged.

## Reusable compositions

| Component | Responsibility | Caller retains |
| --- | --- | --- |
| AppContentFrame | Responsive gutters and maximum content width | Scroll controller and navigation |
| AppPageHeading | Arabic heading hierarchy, optional context and wrapping actions | Copy and allowed actions |
| AppSectionCard | Group heading, subtitle, contextual action and surface | Actual data, state and permission conditions |
| AppActionGroup | Directional wrapping of action widgets | Order, enabled state and callbacks |
| AppSearchEntry | Search entry with a separate filter target | Existing search/filter journey and query state |
| AppIdentityMark | Decorative original identity symbol | Server-backed role and verification badges |
| AppSectionHeader | Adaptive title/action arrangement without clipped Arabic | Existing callback |
| AppLoading/Empty/Error/UnavailableState | Readable feedback with scrolling when necessary | Error/retry behavior and content |
| AppPropertyFacts | Wrapping Arabic/mixed-unit facts | Real model values and availability |

Existing AppButton, AppTextField, AppSurface, AppFilterChip, AppStatusBadge, AppBottomSheet, AppDialog, AppAppBar, AppNavigationBar and property components remain the shared primitives. Screen-specific form fields must keep their validators and controllers; do not replace a FormField with a non-validating text input for convenience.

## Verification

New rendered tests exercise 320/360/412/600 widths, text scale 1 and 2.4, real bundled Arabic fonts, long labels, mixed reference strings and currency, independent search/filter callbacks, contextual actions and short-screen retry reachability. Existing theme contrast and navigation regressions remain intact.

CI saves eight isolated component screenshots under the visual QA artifact. Fixtures live only in tests, explicitly labeled as component examples. They are not authenticated screen evidence and are not runtime demo listings. Phase 1 is not closed until the fresh analyze/tests/APK gate passes and captured layouts are inspected.

Verified 2026-09-14: run `34882892445` passed analyze, all 198 Flutter tests, backend/PostGIS guards and APK. Corrected screenshots from run `34883532270`, artifact `10364505958`, were inspected at all four widths and both scales. Test harness explicitly loads bundled Arabic/Material fonts and SDK Roboto under the existing Latin fallback aliases. No runtime font dependency was added.
