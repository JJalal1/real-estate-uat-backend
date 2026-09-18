# V2 P01 — Foundation, Identity, and Account Experience

## Package goal

Deliver a small, installable V2 baseline that lets the team evaluate the product's visual foundation, Arabic RTL experience, account entry, profile, and publishing-identity verification without the later marketplace and transaction features competing for attention.

## Source baseline

P01 is derived from the accepted current application on `audit/system-stabilization`. Existing authentication, permissions, verification APIs, support review, security boundaries, and audit behavior remain the reference unless a P01 decision explicitly changes them.

## Included

- Arabic-first RTL visual foundation and existing tokenized design system.
- Unified WhatsApp account entry.
- Verification-code flow.
- Four-part name completion.
- Simple personal profile.
- Simple account page.
- Owner / dalal / real-estate-office publishing identity flow.
- Existing support/admin operational workspace retained so identity requests can be reviewed end-to-end.
- P01 package identifier in the UI/build metadata.
- P01-specific acceptance guard tests.

## Intentionally hidden from regular-user P01 navigation

- Marketplace and map.
- Property publishing workspace.
- Messaging and viewings.
- Agreements and transaction tracking.
- Payments and financial account.
- Later services and reporting.

These capabilities are not deleted. They remain source material for later cumulative packages.

## P01 acceptance gate

P01 is not closed until:

1. CI is green.
2. A release APK is produced for UAT.
3. The team can complete account entry and profile flows without external explanation.
4. Owner/dalal/office verification can be submitted and reviewed through the existing UAT operational path.
5. The team reviews typography, color, spacing, navigation, wording, clutter, and perceived ease of use.
6. Blocking feedback is fixed and re-tested.
7. The owner explicitly accepts P01.

After acceptance, the resulting commit becomes the baseline for P02.

Draft review: PR #55. P01 remains unmerged during team UAT.
