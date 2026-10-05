import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active listing editor is finance and Sai free', () {
    final source = File(
      'lib/features/properties/presentation/listing_editor_screen.dart',
    ).readAsStringSync();

    expect(source, contains('الإيجار الشهري بالريال اليمني *'));
    expect(source, isNot(contains('property_sai_configuration_sheet.dart')));
    expect(source, isNot(contains('PropertySaiEnvelope')));
    expect(source, isNot(contains('تحديد السعي')));
    expect(source, isNot(contains('إقرار السعي')));
    expect(source, isNot(contains('السعر + السعي')));
    expect(source, isNot(contains('السعر شامل السعي')));
    expect(source, isNot(contains('مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.')));
    expect(source, isNot(contains('أشهر المقدم *')));
  });

  test('active account property agreement support and admin UI expose no finance action', () {
    final account = File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsStringSync();
    final details = File(
      'lib/features/properties/presentation/property_details_screen.dart',
    ).readAsStringSync();
    final listings = File(
      'lib/features/properties/presentation/my_listings_screen.dart',
    ).readAsStringSync();
    final agreement = File(
      'lib/features/agreements/presentation/agreement_detail_screen.dart',
    ).readAsStringSync();
    final support = File(
      'lib/features/support/presentation/support_tasks_screen.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/features/app_shell/presentation/app_shell_screen.dart',
    ).readAsStringSync();
    final admin = File(
      'lib/features/admin/presentation/admin_dashboard_screen.dart',
    ).readAsStringSync();

    expect(account, isNot(contains('مدفوعاتي')));
    expect(account, isNot(contains('الحساب المالي')));
    expect(account, isNot(contains('FinancialAccountScreen')));
    expect(details, isNot(contains('PropertySaiPublicLine')));
    expect(listings, isNot(contains('إقرار السعي')));
    expect(listings, isNot(contains('financialRepositoryProvider')));
    expect(agreement, isNot(contains('DealFinancialScreen')));
    expect(agreement, isNot(contains('فتح تسوية الصفقة')));
    expect(support, isNot(contains("case 'payment_review':")));
    expect(support, isNot(contains('تأكيد الدفع')));
    expect(shell, isNot(contains('GeneralManagerHomeFinancialOverlay')));
    expect(admin, isNot(contains('الخدمات والمدفوعات')));
    expect(admin, isNot(contains('مدفوعات معلقة')));
  });

  test('dormant finance implementation remains preserved in source', () {
    for (final path in <String>[
      'lib/features/financial/data/financial_repository.dart',
      'lib/features/financial/domain/financial_models.dart',
      'lib/features/financial/presentation/financial_account_screen.dart',
      'lib/features/financial/presentation/deal_financial_screen.dart',
      'lib/features/admin/presentation/general_manager_finance_screens.dart',
      'lib/features/admin/presentation/general_manager_finance_hubs.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: 'historical source missing: $path');
    }

    expect(File('assets/payments/jeeb.png').existsSync(), isTrue);
    expect(File('assets/payments/kuraimi.png').existsSync(), isTrue);
    expect(File('assets/payments/jawali.png').existsSync(), isTrue);
  });

  test('backend current-product policy is explicit and Financial V1 stays gated', () {
    final policy = File(
      '../backend-api-runtime/app/Support/CurrentProductPolicy.php',
    ).readAsStringSync();
    final bootstrap = File(
      '../backend-api-runtime/bootstrap/app.php',
    ).readAsStringSync();
    final provider = File(
      '../backend-api-runtime/app/Providers/AppServiceProvider.php',
    ).readAsStringSync();
    final routes = File('../backend-api-runtime/routes/api.php').readAsStringSync();

    expect(policy, contains('FINANCE_ENABLED = false'));
    expect(policy, contains('SAI_ENABLED = false'));
    expect(bootstrap, contains('CurrentProductPolicy::financeEnabled()'));
    expect(provider, isNot(contains('FinancialPropertyController::class')));
    expect(provider, isNot(contains('FinancialAgreementContractController::class')));
    expect(routes, contains('CurrentProductPolicy::saiEnabled()'));
    expect(routes, contains('CurrentProductPolicy::financeEnabled()'));
  });
}
