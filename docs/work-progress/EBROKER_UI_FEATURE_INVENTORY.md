# Experimental UI Feature Inventory

Stable source: `46b8fed8fd119b223d4a1e67312d38ff9429e569`.

This checklist covers every Dart presentation file, every declared GoRouter path, and source anchors for all detected actions, forms, validation, dialogs, state branches, permissions, providers, and API calls. The JSON companion retains file/line references. Mechanical coverage is complete; manual journey and runtime verification remain open until explicitly marked. Do not equate anchor counts with unique features.

## Architecture and locked boundaries

- Flutter Material 3, Arabic locale, bundled NotoSansArabic, Riverpod 2.6.1, GoRouter 15, Dio 5, MapLibre 0.22.
- `main.dart` → `appRouterProvider` → role-aware lazy `IndexedStack` shell. Auth gates stay at original entry points; Laravel remains authoritative.
- Existing theme/tokens/semantic colors/shared components are in `core/theme` and `core/widgets`. Forms and screen-specific mutation methods remain in their current feature.
- Repositories use existing required/optional auth options. Secure session and native media picker remain unchanged. Do not add client-side security decisions.

## Persona and navigation matrix

| Mode | Existing tabs, in order | Boundary |
| --- | --- | --- |
| Anonymous | العقارات · حسابي | Public published discovery; auth-gated private actions |
| Regular / buyer | العقارات · الرسائل · المعاينات · حسابي | Active/verified phone as required by gate |
| Verified owner / broker / office | العقارات · إعلاناتي · الرسائل · المعاينات · حسابي | Existing `hasVerifiedPublishingProfile`; listing eligibility remains backend-controlled |
| Support agent | لوحة الدعم · الوارد · مهامي · الرسائل · حسابي | Shared queue / first valid claim; participant-only normal chat |
| Support manager | لوحة الفريق · الأعمال · الفريق · الرسائل · حسابي | Existing assignment / acting-as-agent / escalation permissions |
| GM / super admin | الرئيسية · السوق · الإدارة · التقارير · حسابي | Exactly five; financial sections stay inside existing hubs |

Professional identity is separate from operational role. An unverified broker must not gain advertiser publication permissions or support capabilities.

## Journey checklist

### Public discovery

- [ ] Manual preservation and redesign verification complete.
- Roles: anonymous/regular/advertiser.
- Existing surfaces/actions: MapScreen, search sheet, purpose/type quick filters, advanced price/area/room/radius filters, map/list switch, sorting, map bounds, drawn-area interaction, geolocation, pagination, recent-search restoration, saved-search handoff, selected-property card.
- Locked: Nearby provider + PropertyRepository; public unpublished exclusion; no invented properties.

### Favorites and comparison

- [ ] Manual preservation and redesign verification complete.
- Roles: authenticated account.
- Existing surfaces/actions: favorite handoff preserves intent, save/remove persisted server-side, unavailable saved property, selection/compare limits, comparison table, clear selection.
- Locked: FavoritesRepository; account-scoped auth, server states; PropertyCompareScreen.

### Saved searches

- [ ] Manual preservation and redesign verification complete.
- Roles: authenticated account.
- Existing surfaces/actions: list/create/edit/enable/delete saved searches, current discovery criteria capture, results navigation and notification preferences.
- Locked: SavedSearchRepository, existing models and filters; no fake counts.

### Property details

- [ ] Manual preservation and redesign verification complete.
- Roles: public plus allowed private actions.
- Existing surfaces/actions: gallery/fullscreen/zoom, price and currency, location/facts/description, trust flags, advertiser information, Sai public line, market context, share/favorite/contact, community/reports, similar properties.
- Locked: PropertyDetails model; original contact/viewing auth, published availability, public privacy and identity boundary.

### Listing editor

- [ ] Manual preservation and redesign verification complete.
- Roles: eligible advertiser.
- Existing surfaces/actions: type/purpose/facts, sale tenure, rental settlement/monthly rent/term/advance, Arabic price words, address/GPS/map, unit/floor/building identity, land boundary, public images, ownership relationship proof, Sai configuration/terms, save draft/preview/explicit submit.
- Locked: PropertyRepository + financial/Sai integration; preserve validation order, working draft, correction reason, exact duplicate/identity server responses and representation claims.

### Listing management

- [ ] Manual preservation and redesign verification complete.
- Roles: own advertiser data.
- Existing surfaces/actions: overview/lifecycle filters, open/edit/preview/submit/resubmit/refresh, review reason, identity/support state, financial status, Sai oath attestation, available lifecycle actions.
- Locked: Original state-dependent actions; oath wording and attestation API remain literal.

### Messaging

- [ ] Manual preservation and redesign verification complete.
- Roles: participants; separately permissioned reported cases.
- Existing surfaces/actions: inbox/unread, property-linked conversation, newest/older pages, read state, composer/retry/client_message_id, report, attachments if supported, property context, linked agreement/viewing controls.
- Locked: Single MessageRepository; no second messenger or wider support access; unavailable listings retain participant history.

### Viewing

- [ ] Manual preservation and redesign verification complete.
- Roles: requester/advertiser/allowed manager.
- Existing surfaces/actions: request sheet, dates/times/notes, exact booking navigation, confirm/reject/reschedule/cancel/complete, replacement proposal acceptance.
- Locked: BookingRepository locks/state semantics; proposer cannot confirm own replacement; terminal states remain terminal.

### Account and authentication

- [ ] Manual preservation and redesign verification complete.
- Roles: all personas.
- Existing surfaces/actions: WhatsApp start/verify, legacy auth/reset routes, profile completion/update, phone verification, account group links, logout/session clearing.
- Locked: AuthController/Repository and auth return intent; no alternate identity system.

### Professional KYC

- [ ] Manual preservation and redesign verification complete.
- Roles: owner/broker/office and authorized reviewers.
- Existing surfaces/actions: select professional type, identity/location/work areas/specializations, camera-only selfie, supported document picker, office details and evidence, pending/correction/rejected/approved states.
- Locked: AccountVerification/BrokerVerification repositories; unchanged required files/flags/eligibility.

### Services and advertiser workspace

- [ ] Manual preservation and redesign verification complete.
- Roles: backend capabilities.
- Existing surfaces/actions: free services hub, professional priorities, property journey, real counts, listings/messages/viewings/agreements links, planned/deferred service wording.
- Locked: ServicesHub capabilities; no paid promotion or deferred request/matching activation.

### Agreements and rental contracts

- [ ] Manual preservation and redesign verification complete.
- Roles: existing eligible parties.
- Existing surfaces/actions: conversation card, agreement list/detail/terms/accept/reject/cancel/amend as offered, rental form/detail/actions, dates and notes, transaction/financial entry points.
- Locked: AgreementRepository + server actions; no invented legal states or notarization claims.

### Financial V1

- [ ] Manual preservation and redesign verification complete.
- Roles: buyer/advertiser/support/GM under existing permissions.
- Existing surfaces/actions: deal, direct confirmation, payment mode/method, official payment details/copy, anti-fraud text, manual proof upload/submit, pending/correction/reject/confirmed, advertiser account/receivables/payouts, holds, disputes, refunds, admin filters/method configuration.
- Locked: FinancialRepository; no payment execution; preserve oath, irreversible confirmations and server-provided amounts.

### Support

- [ ] Manual preservation and redesign verification complete.
- Roles: user/agent/manager.
- Existing surfaces/actions: create/open case, history/reply/evidence, inbox/mine/all/completed, claim/assign/return/reject/approve/escalate, payment review, account verification, user context and work log.
- Locked: Shared queue claim first-wins; actingAsAgent and audited private evidence access retained.

### Listing review and identity

- [ ] Manual preservation and redesign verification complete.
- Roles: authorized support/manager.
- Existing surfaces/actions: review workspace/case, advertiser verification, public media/private proof, duplicate candidates, attach correct asset or reason, publish/return/reject/block, broker listing verification.
- Locked: Property Identity V2 + existing duplicate checks and review ownership; no Flutter-authoritative decisions.

### GM administration and reporting

- [ ] Manual preservation and redesign verification complete.
- Roles: GM/authorized admin.
- Existing surfaces/actions: home financial overlay, market/map, administration/reports financial hubs, accounts directory, team, operations, metrics, financial sections, access roles/permissions, settings, audit log.
- Locked: GeneralManagerRepository/AdminWorkspaceRepository; no sixth tab and no role widening.

### Regions and developments

- [ ] Manual preservation and redesign verification complete.
- Roles: existing authorized/public entry points.
- Existing surfaces/actions: region list/map/edit/approval, development/project list/filter/details/unit viewing, development admin create/edit.
- Locked: RegionRepository and DevelopmentRepository; investigate ProjectsScreen local data and route reachability, preserve existing legitimate journeys.

### Notifications and community

- [ ] Manual preservation and redesign verification complete.
- Roles: eligible account/user.
- Existing surfaces/actions: list/read/actions, exact entity deep links, preference toggles, comments/replies, ratings, reports/reported-conversation review.
- Locked: Existing notification destinations/preferences and CommunityRepository; preserve authorization and target references.

## Routes

Every declared route is preserved. Most operational/detail subpages also use `MaterialPageRoute`; those are indexed in the JSON and per-file checklist.

| Route | Existing builder / gate source |
| --- | --- |
| `/` | `AppShellScreen` |
| `/auth` | `AuthScreen` |
| `/verify-phone` | `PhoneVerificationScreen` |
| `/complete-profile` | `Stage6AuthGate`, `CompleteProfileScreen` |
| `/account-verification` | `Stage6AuthGate`, `AccountVerificationScreen` |
| `/forgot-password` | `ForgotPasswordScreen` |
| `/profile` | `Stage6AuthGate`, `ProfileScreen` |
| `/admin/access` | `Stage6AuthGate`, `AccessControlScreen` |
| `/admin/dashboard` | `Stage6AuthGate`, `AdminDashboardScreen` |
| `/admin/settings` | `Stage6AuthGate`, `PlatformSettingsScreen` |
| `/admin/audit-log` | `Stage6AuthGate`, `AuditLogScreen` |
| `/admin/listing-review` | `Stage6AuthGate`, `ListingReviewScreen` |
| `/broker/account-verification` | `Stage6AuthGate`, `BrokerAccountVerificationScreen` |
| `/admin/broker-account-verifications` | `Stage6AuthGate`, `BrokerVerificationAdminScreen` |
| `/admin/account-verifications` | `Stage6AuthGate`, `AccountVerificationAdminScreen` |
| `/admin/regions` | `Stage6AuthGate`, `RegionsManagementScreen` |
| `/messages` | `Stage6AuthGate`, `MessagesScreen` |
| `/messages/:id` | `Stage6AuthGate`, `ConversationScreen` |
| `/agreements` | `Stage6AuthGate`, `AgreementsScreen` |
| `/agreements/:id` | `Stage6AuthGate`, `AgreementDetailScreen` |
| `/rental-contracts/:id` | `Stage6AuthGate`, `RentalContractDetailScreen` |
| `/notifications` | `Stage6AuthGate`, `NotificationsScreen` |
| `/admin/message-reports` | `Stage6AuthGate`, `ConversationReportsScreen` |
| `/bookings` | `Stage6AuthGate`, `BookingsScreen` |
| `/services` | `Stage6AuthGate`, `ServicesScreen` |
| `/support` | `Stage6AuthGate`, `SupportCenterScreen` |
| `/admin/support` | `Stage6AuthGate`, `SupportAdminScreen` |
| `/support/workspace` | `Stage6AuthGate`, `SupportWorkspaceScreen` |
| `/support/users` | `Stage6AuthGate`, `SupportUsersScreen` |
| `/support/worklog` | `Stage6AuthGate`, `SupportWorkLogScreen` |
| `/properties/:id` | `PropertyDetailsScreen` |
| `/add-property` | `Stage6AuthGate`, `AddPropertyWizardScreen` |
| `/my-listings` | `Stage6AuthGate`, `MyListingsScreen` |
| `/favorites` | `Stage6AuthGate`, `FavoritesScreen` |
| `/property-market` | `MapScreen` |

## Complete presentation-file checklist

Each row stays open until shared design adoption, RTL/responsive rendering, loading/error/empty states where applicable, original callbacks/navigation/API/permissions and relevant tests are verified. A theme change alone does not close a row.

| Done | File | Source widgets / screens | Action anchors | Form anchors |
| --- | --- | --- | ---: | ---: |
| [ ] | `mobile_app/lib/features/account/presentation/access_control_screen.dart` | AccessControlScreen | 17 | 13 |
| [ ] | `mobile_app/lib/features/account/presentation/account_screen.dart` | AccountScreen | 5 | 0 |
| [ ] | `mobile_app/lib/features/account/presentation/account_verification_admin_screen.dart` | AccountVerificationAdminScreen | 12 | 14 |
| [ ] | `mobile_app/lib/features/account/presentation/account_verification_screen.dart` | AccountVerificationScreen | 14 | 27 |
| [ ] | `mobile_app/lib/features/account/presentation/auth_gate.dart` | Stage6AuthGate | 6 | 0 |
| [ ] | `mobile_app/lib/features/account/presentation/auth_screen.dart` | AuthScreen | 2 | 4 |
| [ ] | `mobile_app/lib/features/account/presentation/broker_account_verification_screen.dart` | BrokerAccountVerificationScreen | 7 | 0 |
| [ ] | `mobile_app/lib/features/account/presentation/broker_verification_admin_screen.dart` | BrokerVerificationAdminScreen | 5 | 2 |
| [ ] | `mobile_app/lib/features/account/presentation/complete_profile_screen.dart` | CompleteProfileScreen | 2 | 4 |
| [ ] | `mobile_app/lib/features/account/presentation/forgot_password_screen.dart` | ForgotPasswordScreen | 2 | 9 |
| [ ] | `mobile_app/lib/features/account/presentation/phone_verification_screen.dart` | PhoneVerificationScreen | 4 | 3 |
| [ ] | `mobile_app/lib/features/account/presentation/profile_screen.dart` | ProfileScreen | 1 | 6 |
| [ ] | `mobile_app/lib/features/admin/presentation/admin_dashboard_screen.dart` | AdminDashboardScreen | 4 | 2 |
| [ ] | `mobile_app/lib/features/admin/presentation/audit_log_screen.dart` | AuditLogScreen | 2 | 2 |
| [ ] | `mobile_app/lib/features/admin/presentation/general_manager_accounts_screen.dart` | GeneralManagerAccountsScreen | 15 | 9 |
| [ ] | `mobile_app/lib/features/admin/presentation/general_manager_finance_hubs.dart` | GeneralManagerHomeFinancialOverlay, GeneralManagerAdministrationFinancialHubScreen, GeneralManagerReportsFinancialHubScreen | 5 | 0 |
| [ ] | `mobile_app/lib/features/admin/presentation/general_manager_finance_screens.dart` | GeneralManagerPaymentMethodsScreen, GeneralManagerFinanceWorkspaceScreen | 16 | 37 |
| [ ] | `mobile_app/lib/features/admin/presentation/general_manager_pages.dart` | GeneralManagerHomeScreen, GeneralManagerMarketScreen, GeneralManagerAdministrationScreen, GeneralManagerReportsScreen, GeneralManagerTeamScreen, GeneralManagerMapScreen | 46 | 6 |
| [ ] | `mobile_app/lib/features/admin/presentation/platform_settings_screen.dart` | PlatformSettingsScreen | 3 | 5 |
| [ ] | `mobile_app/lib/features/agreements/presentation/agreement_detail_screen.dart` | AgreementDetailScreen | 11 | 3 |
| [ ] | `mobile_app/lib/features/agreements/presentation/agreement_forms.dart` |  | 6 | 65 |
| [ ] | `mobile_app/lib/features/agreements/presentation/agreements_screen.dart` | AgreementsScreen | 5 | 0 |
| [ ] | `mobile_app/lib/features/agreements/presentation/conversation_agreement_card.dart` | ConversationAgreementCard | 2 | 0 |
| [ ] | `mobile_app/lib/features/agreements/presentation/rental_contract_detail_screen.dart` | RentalContractDetailScreen | 12 | 3 |
| [ ] | `mobile_app/lib/features/app_shell/presentation/app_shell_screen.dart` | AppShellScreen | 3 | 0 |
| [ ] | `mobile_app/lib/features/bookings/presentation/booking_request_sheet.dart` | BookingRequestSheet | 4 | 7 |
| [ ] | `mobile_app/lib/features/bookings/presentation/bookings_screen.dart` | BookingsScreen | 12 | 5 |
| [ ] | `mobile_app/lib/features/community/presentation/community_dialogs.dart` | CommunityRatingDialogResult, CommunityReportDialogResult | 10 | 21 |
| [ ] | `mobile_app/lib/features/community/presentation/listing_community_screen.dart` | ListingCommunityScreen | 12 | 0 |
| [ ] | `mobile_app/lib/features/developments/presentation/development_admin_screen.dart` | DevelopmentAdminScreen | 14 | 24 |
| [ ] | `mobile_app/lib/features/developments/presentation/development_details_screen.dart` | DevelopmentDetailsScreen | 1 | 0 |
| [ ] | `mobile_app/lib/features/developments/presentation/developments_screen.dart` | DevelopmentsScreen | 5 | 3 |
| [ ] | `mobile_app/lib/features/financial/presentation/deal_financial_screen.dart` | DealFinancialScreen | 15 | 10 |
| [ ] | `mobile_app/lib/features/financial/presentation/financial_account_screen.dart` | FinancialAccountScreen | 6 | 0 |
| [ ] | `mobile_app/lib/features/financial/presentation/receivable_payment_screen.dart` | ReceivablePaymentScreen | 7 | 10 |
| [ ] | `mobile_app/lib/features/map/presentation/map_screen.dart` | NearbyQuery, MapScreen | 48 | 24 |
| [ ] | `mobile_app/lib/features/messages/presentation/conversation_reports_screen.dart` | ConversationReportsScreen | 5 | 0 |
| [ ] | `mobile_app/lib/features/messages/presentation/conversation_screen.dart` | ConversationScreen | 15 | 11 |
| [ ] | `mobile_app/lib/features/messages/presentation/messages_screen.dart` | MessagesScreen | 4 | 0 |
| [ ] | `mobile_app/lib/features/messages/presentation/notification_preferences_screen.dart` | NotificationPreferencesScreen | 8 | 2 |
| [ ] | `mobile_app/lib/features/messages/presentation/notifications_screen.dart` | NotificationsScreen | 6 | 0 |
| [ ] | `mobile_app/lib/features/projects/presentation/projects_screen.dart` | ProjectsScreen | 12 | 0 |
| [ ] | `mobile_app/lib/features/properties/presentation/add_property_wizard_screen.dart` | AddPropertyWizardScreen | 0 | 0 |
| [ ] | `mobile_app/lib/features/properties/presentation/favorites_screen.dart` | FavoritesScreen | 6 | 2 |
| [ ] | `mobile_app/lib/features/properties/presentation/listing_editor_screen.dart` | ListingEditorScreen | 33 | 71 |
| [ ] | `mobile_app/lib/features/properties/presentation/my_listings_screen.dart` | MyListingsScreen | 16 | 7 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_compare_screen.dart` | PropertyCompareScreen | 1 | 0 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_details_screen.dart` | PropertyDetailsScreen | 14 | 8 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_land_boundary_picker_screen.dart` | PropertyLandBoundarySelection, PropertyLandBoundaryPickerScreen | 3 | 0 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_location_picker_screen.dart` | PropertyLocationSelection, PropertyLocationPickerScreen | 2 | 0 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_market_context_card.dart` | PropertyMarketContextCard | 1 | 1 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_sai_configuration_sheet.dart` |  | 6 | 5 |
| [ ] | `mobile_app/lib/features/properties/presentation/property_sai_public_line.dart` | PropertySaiPublicLine, PropertySaiDisplayLine | 1 | 1 |
| [ ] | `mobile_app/lib/features/properties/presentation/saved_search_builder_screen.dart` | SavedSearchBuilderScreen | 7 | 43 |
| [ ] | `mobile_app/lib/features/properties/presentation/saved_searches_screen.dart` | SavedSearchesScreen, SavedSearchResultsScreen | 6 | 2 |
| [ ] | `mobile_app/lib/features/regions/presentation/platform_regions_screen.dart` | PlatformRegionsScreen | 6 | 5 |
| [ ] | `mobile_app/lib/features/regions/presentation/regions_management_screen.dart` | RegionsManagementScreen | 16 | 24 |
| [ ] | `mobile_app/lib/features/reviews/presentation/broker_listing_verifications_screen.dart` | BrokerListingVerificationsScreen | 7 | 6 |
| [ ] | `mobile_app/lib/features/reviews/presentation/listing_review_screen.dart` | ListingReviewScreen | 0 | 0 |
| [ ] | `mobile_app/lib/features/reviews/presentation/listing_review_workspace_screen.dart` | ListingReviewWorkspaceScreen, ListingReviewCaseScreen | 14 | 21 |
| [ ] | `mobile_app/lib/features/services/presentation/professional_workspace_screen.dart` | ProfessionalWorkspaceScreen | 9 | 2 |
| [ ] | `mobile_app/lib/features/services/presentation/property_journey_screen.dart` | PropertyJourneyScreen | 9 | 2 |
| [ ] | `mobile_app/lib/features/services/presentation/services_screen.dart` | ServicesScreen | 9 | 2 |
| [ ] | `mobile_app/lib/features/support/presentation/account_verification_support_screen.dart` | AccountVerificationSupportScreen | 11 | 0 |
| [ ] | `mobile_app/lib/features/support/presentation/support_admin_screen.dart` | SupportAdminScreen | 21 | 15 |
| [ ] | `mobile_app/lib/features/support/presentation/support_center_screen.dart` | SupportCenterScreen | 11 | 12 |
| [ ] | `mobile_app/lib/features/support/presentation/support_tasks_screen.dart` | SupportTasksScreen | 46 | 19 |
| [ ] | `mobile_app/lib/features/support/presentation/support_users_screen.dart` | SupportUsersScreen | 5 | 3 |
| [ ] | `mobile_app/lib/features/support/presentation/support_work_log_screen.dart` | SupportWorkLogScreen | 2 | 4 |
| [ ] | `mobile_app/lib/features/support/presentation/support_workspace_pages.dart` | SupportAgentHomeScreen, SupportManagerHomeScreen, PlatformAdminHomeScreen, SupportTeamScreen, PlatformReviewsScreen, PlatformOperationsScreen | 25 | 3 |
| [ ] | `mobile_app/lib/features/support/presentation/support_workspace_screen.dart` | SupportWorkspaceScreen | 3 | 2 |

Also preserve `_RouteErrorScreen` and all shared component states in `core/widgets/app_components.dart`.

## Repository / API interaction inventory

Exact method/path/auth/payload source anchors are in `EBROKER_UI_SOURCE_INVENTORY.json`; all repository and model files are locked by SHA-256. The index deliberately does not rewrite endpoint contracts as assumptions.

| Repository file | API/auth/payload anchors |
| --- | ---: |
| `mobile_app/lib/features/account/data/access_control_repository.dart` | 18 |
| `mobile_app/lib/features/account/data/account_verification_repository.dart` | 23 |
| `mobile_app/lib/features/account/data/auth_controller.dart` | 0 |
| `mobile_app/lib/features/account/data/auth_repository.dart` | 29 |
| `mobile_app/lib/features/account/data/auth_return_intent.dart` | 0 |
| `mobile_app/lib/features/account/data/broker_verification_repository.dart` | 22 |
| `mobile_app/lib/features/admin/data/admin_workspace_repository.dart` | 6 |
| `mobile_app/lib/features/admin/data/general_manager_repository.dart` | 9 |
| `mobile_app/lib/features/agreements/data/agreement_repository.dart` | 39 |
| `mobile_app/lib/features/bookings/data/booking_repository.dart` | 11 |
| `mobile_app/lib/features/community/data/community_repository.dart` | 24 |
| `mobile_app/lib/features/developments/data/development_repository.dart` | 24 |
| `mobile_app/lib/features/financial/data/financial_repository.dart` | 53 |
| `mobile_app/lib/features/map/data/property_discovery_history_store.dart` | 0 |
| `mobile_app/lib/features/messages/data/message_repository.dart` | 34 |
| `mobile_app/lib/features/messages/data/notification_preference_repository.dart` | 7 |
| `mobile_app/lib/features/properties/data/favorites_repository.dart` | 15 |
| `mobile_app/lib/features/properties/data/property_market_repository.dart` | 2 |
| `mobile_app/lib/features/properties/data/property_repository.dart` | 44 |
| `mobile_app/lib/features/properties/data/saved_search_repository.dart` | 14 |
| `mobile_app/lib/features/regions/data/region_repository.dart` | 16 |
| `mobile_app/lib/features/reviews/data/listing_review_repository.dart` | 23 |
| `mobile_app/lib/features/services/data/professional_workspace_repository.dart` | 3 |
| `mobile_app/lib/features/services/data/service_repository.dart` | 24 |
| `mobile_app/lib/features/support/data/account_verification_support_repository.dart` | 9 |
| `mobile_app/lib/features/support/data/support_repository.dart` | 43 |
| `mobile_app/lib/features/support/data/support_workspace_repository.dart` | 47 |

## Regression checklist

- [ ] Flutter dependency resolution, analysis and all existing tests at exact source SHA.
- [ ] Compile-time UAT endpoint guard with Frankfurt build constants.
- [ ] Laravel full suite and PostgreSQL/PostGIS schema/security regression in disposable CI.
- [ ] All captured locked source hashes match.
- [ ] Role/auth/deep-link/source-contract tests retained.
- [ ] RTL widths 320/360/412/600, Arabic long labels, mixed text/prices, keyboard and text scale 1/1.3/2.
- [ ] Main screens rendered and evidence saved; live API integration QA uses Frankfurt only.
- [ ] Experimental APK, APK SHA-256 and build source evidence.
- [ ] Stable branch heads unchanged by this work; no Production actions.
