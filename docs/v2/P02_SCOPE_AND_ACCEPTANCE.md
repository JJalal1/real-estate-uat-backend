# V2 P02 — Marketplace, Search, and Property Discovery

## Package goal

Deliver an installable cumulative package on top of P01 so the team can evaluate the complete discovery journey: start from location, search and filter, switch between map/list, inspect a property, save favorites, and create a private property request when no suitable listing is found.

## Included

- P01 foundation, identity, authentication, and account experience.
- Discovery-first Arabic RTL home.
- Public map and list browsing for guests.
- Buy/rent and property-type filters.
- Search by listing/address text.
- Price filters with explicit denomination and no automatic conversion.
- Map area selection.
- Property cards and details using the existing stable listing data.
- Original local area-unit display when available.
- Favorites for authenticated users.
- Private property requests stored per account.
- Private-request matching by property criteria, currency denomination, location, and original local area unit.
- Instant matching notification foundation.
- Clear loading, empty, and error states.

## Privacy invariant

Private property requests are account-bound. They are not exposed to dalals, offices, or other advertisers through a public/advertiser endpoint.

## Intentionally not surfaced in P02 regular-user navigation

- Full listing creation and advertiser workspace.
- Duplicate property / representation management.
- Messaging and viewing workflows.
- Deal tracking.
- Commission and platform receivables.
- Support/admin operating screens beyond internal staff access already required for UAT.

Those capabilities remain in the source baseline for later cumulative packages.

## Acceptance gate

P02 remains open until:

1. Backend, PostgreSQL/PostGIS, Flutter analysis, Flutter tests, and APK build are green.
2. The team can browse as guest, search, filter, switch map/list, and open details.
3. Authentication-gated favorites and private requests return the user to a useful flow.
4. No automatic currency conversion occurs.
5. Local area units are preserved/displayed rather than silently converted using a global assumption.
6. The team reviews clutter, navigation, Arabic wording, map usability, cards, filters, empty states, and perceived speed.
7. Blocking feedback is fixed and re-tested.
8. Product owner explicitly accepts P02.

After acceptance, the accepted P02 commit becomes the baseline for P03.
