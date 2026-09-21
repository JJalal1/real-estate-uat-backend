# Phase 1 — Accepted Design System

Status: ACCEPTED FOR IMPLEMENTATION
Source: W3A Design System Specification, reviewed against current Phase 1 branch and accepted IA
Branch: `phase1/ux-product-foundation`

## Design direction

Use one Arabic-first, RTL-first, light Material 3 design system for the existing Flutter application. Extend the current `AppTheme` rather than replacing the app architecture. The system uses restrained green primary actions, neutral surfaces, explicit semantic state colors, readable Arabic typography, 4/8-based spacing, content-driven sizing, and reusable presentation primitives.

This is a presentation foundation only. It must not change backend authorization, API contracts, routes, database state, listing workflow semantics, support claim ownership, professional verification rules, or private-data boundaries.

## Accepted color roles

Keep `AppTheme.light` as the single composition point and keep `#0B8A55` only as the brand seed.

Core Material roles:
- primary `#0B7547`
- onPrimary `#FFFFFF`
- primaryContainer `#E5F5EC`
- onPrimaryContainer `#075B39`
- secondary `#1778B8`
- onSecondary `#FFFFFF`
- secondaryContainer `#E7F2FA`
- onSecondaryContainer `#0D4D75`
- surface `#FFFFFF`
- onSurface `#111820`
- onSurfaceVariant `#505B65`
- surfaceContainerLow `#F5F7F8`
- surfaceContainer `#F0F3F4`
- surfaceContainerHigh `#E7ECEF`
- surfaceContainerHighest `#DDE4E8`
- outline `#78858F`
- outlineVariant `#C9D2D7`
- error `#B3261E`
- errorContainer `#F9DEDC`
- onErrorContainer `#410E0B`
- inverseSurface `#24313A`
- onInverseSurface `#FFFFFF`

Custom semantic roles belong in one `ThemeExtension`, `AppSemanticColors`:
- success / successContainer
- warning / warningContainer
- info / infoContainer
- neutral / neutralContainer
- disabledContainer / onDisabledContainer / disabledOutline
- skeletonBase / skeletonHighlight

Color alone never communicates state. Review approval, publication, professional verification, claim ownership, escalation, availability, and rejection remain separate facts.

### Review clarification

Use `ColorScheme.primary` or `onSurface` for emphasized price text on a normal white/surface background. `onPrimaryContainer` is reserved for content actually placed on `primaryContainer`; do not use paired Material foreground roles on unrelated backgrounds merely because the hue is attractive.

## Accepted token namespaces

Use these shared namespaces:
- `AppTheme`
- `AppSemanticColors`
- `AppTypography`
- `AppSpacing`
- `AppLayout`
- `AppRadii`
- `AppBorderWidths`
- `AppElevation`
- `AppSizes`
- `AppMotion`
- `AppOpacity`

Do not introduce a generated token pipeline, a second theme engine, per-role themes, screen-specific token namespaces, or a new component-library dependency.

## Layout tokens

Spacing primitives:
`0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`

Key layout rules:
- compact page gutter: 16
- wide page gutter: 24
- wide breakpoint: 600
- narrow breakpoint: 360
- content max width for text/forms/lists: 840
- section gap: 32
- group gap: 24
- item gap: 12
- field gap: 16
- inline gap: 8
- surface padding: 16
- compact surface padding: 12
- dialog padding: 24

Radii:
- small 8
- control 12
- card 16
- modal 24
- pill 999

Borders:
- standard 1
- emphasized 2

Elevation:
- flat 0
- raised 1
- floating 3
- modal 6

Minimum sizes:
- touch target 48 x 48
- button min height 48
- field min height 56 excluding helper/error text
- chip visual min height 32 with 48 touch target
- badge min height 28
- app bar min height 64 plus system inset
- navigation content min height 80 plus system inset and must grow for scaled/wrapped labels

Content-bearing cards, rows, sheets, and navigation must grow before shrinking text, touch targets, or gutters.

## Typography

Target typography family: `Noto Sans Arabic`, weights 400/500/600/700, with zero Arabic letter spacing. The accepted text scale is:
- headlineLarge 28/40, 700
- headlineMedium 24/36, 700
- headlineSmall 22/32, 600
- titleLarge 20/32, 600
- titleMedium 18/28, 600
- titleSmall 16/24, 600
- bodyLarge 16/28, 400
- bodyMedium 14/24, 400
- bodySmall 12/20, 400
- labelLarge 16/24, 600
- labelMedium 14/20, 600
- labelSmall 12/20, 600

Display styles may exist in the scale but are not permission to create marketing/hero surfaces in Phase 1.

### Typography implementation gate

The family choice is accepted as the target, but binary font assets must not be added blindly. W3B1 must establish the scale/tokens without introducing a new font binary or package dependency. Font bundling/activation is a separate small implementation step after repository/licensing/build handling is explicit and must be visually validated later in W3V. Until then, preserve a safe system fallback and do not configure a family name that is not actually available to the build.

## Accepted reusable component vocabulary

Foundation:
- `AppTheme`
- `AppSemanticColors`
- token groups above

Controls:
- `AppButton`
- `AppIconButton`
- `AppTextField`
- `AppFilterChip`

Surface/layout:
- `AppSurface`
- `AppSectionHeader`
- `AppListRow`

Feedback:
- `AppStatusBadge`
- `AppInlineMessage`
- `AppLoadingState`
- `AppSkeleton`
- `AppEmptyState`
- `AppErrorState`
- `AppUnavailableState`

Chrome/overlays:
- `AppAppBar`
- `AppNavigationBar`
- `AppBottomSheet`
- `AppDialog`

Property composition:
- `AppPropertyCard`
- `AppPropertyMedia`
- `AppPropertyPrice`
- `AppPropertyFacts`

Shared presentation components receive display data, state/tone, and callbacks. They must not read Riverpod providers, call repositories, resolve roles, grant permissions, create domain state, or interpret backend authorization.

## Component rules

Buttons:
- one dominant primary action per action group;
- secondary uses outline; tonal uses primary container; tertiary uses text; destructive uses error semantics;
- all independent actions keep a 48 x 48 minimum target;
- busy state prevents duplicate activation without pretending the operation succeeded.

Fields:
- persistent visible labels;
- readable helper/error text that can wrap;
- focus and error may coexist;
- preserve entered values after validation/server errors;
- first invalid field is revealed on failed submit;
- shared field primitives never parse backend exceptions or invent validation rules.

Chips/status:
- selected filters use container + explicit selected cue;
- statuses use text plus tone, never color alone;
- unknown values display a neutral unavailable/unknown state rather than inferring success.

Property cards:
- no fixed overall height;
- title up to two preview lines by default but expands under large text;
- price + currency must remain fully visible;
- location can use up to two preview lines;
- facts wrap and never fabricate missing values;
- no fake featured ribbon, rating, favorite, trust badge, or unavailable state without real current data;
- no local-only Favorites substitute.

## Navigation visual rules

The accepted IA remains authoritative. W3 does not change destination structure.

Navigation labels remain visible and are never `FittedBox`-shrunk. The bar must adapt in height for Arabic wrapping and text scaling. Icons remain a stable size; selection must not shift layout. Every destination remains a full semantic/tappable target.

## Loading, empty, error, and unavailable grammar

Use one reusable grammar:
- clear Arabic title;
- short explanation;
- existing relevant recovery action;
- preserve current context and prior readable data where safe.

Collection refresh keeps existing data visible. Pagination failure keeps previous results and shows a footer retry. Image failure does not invalidate the rest of a property card. Mutation timeout/conflict is never automatically retried by a generic component.

Published-property discovery remains public. 401/403/404/409/422/429 presentation must reflect the real backend outcome and never imply access or success that the server did not grant.

## RTL and accessibility

Use logical-direction APIs (`EdgeInsetsDirectional`, `AlignmentDirectional`, etc.). Do not manually reverse both data and RTL layout. Maps, media, documents, photos, logos, coordinates, and stored text are never mirrored/reversed.

Minimum acceptance expectations:
- every independent target >= 48 x 48;
- enabled text contrast >= 4.5:1;
- essential focus/control graphics >= 3:1;
- platform text scaling and bold text respected;
- no shrink-to-fit for essential text;
- keyboard must not cover active controls;
- actions stack/reflow before typography or targets shrink;
- Arabic error/correction reasons remain fully readable;
- screen-reader semantics expose full labels, state, price/currency, selected/busy/disabled state.

## Consumer vs operational surfaces

One theme and component language serves consumers, support, managers, and platform owners. Staff screens may use denser metadata spacing, but not smaller interaction targets or unreadable text. Operational state does not use a separate admin palette.

Private proof documents, verification evidence, reported-conversation context, claim ownership, and staff-only actions never leak into public marketplace components.

## Implementation sequence

W3A is accepted.

Next tasks are deliberately small:
1. **W3B1 — token/theme scaffolding:** implement color scheme, semantic extension, spacing/layout/radius/border/elevation/size/motion/opacity constants, and explicit text scale using the currently available font fallback. No font binary, no shared component wrappers, no screen redesign.
2. **W3B2 — typography asset integration:** separate task only after W3B1 review; add/activate the accepted Arabic family with explicit license/build handling. No broad screen migration.
3. **W3C1+ — shared component primitives:** split controls, feedback, property primitives, and chrome into small reviewed tasks rather than one large component rewrite.
4. **W3V — rendered visual validation:** required when callable Computer Use/emulator/device access becomes available, before broad visual rollout.
5. W4 does not start until the design-system implementation is accepted at code level.

## Non-goals

No route migration, no shell redesign, no feature activation, no payment, no Production, no backend/database/security semantics change, no SDK/package upgrade, no new state-management architecture, and no global screen rewrite are authorized by this document.