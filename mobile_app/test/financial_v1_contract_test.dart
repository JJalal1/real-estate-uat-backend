import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/financial/data/financial_repository.dart';
import 'package:real_estate_mobile/features/financial/domain/financial_models.dart';
import 'package:real_estate_mobile/features/support/presentation/support_payment_review_screen.dart';

import 'support/owner_ux_fixtures.dart';

class _SupportPaymentRepository implements FinancialRepository {
  final decisions = <(int, String, String?, bool)>[];
  int proofLoads = 0;

  @override
  Future<FinancialPayment> adminPayment(
    int paymentId, {
    bool actingAsAgent = false,
  }) async => FinancialPayment(
        id: paymentId,
        reference: 'PAY-TEST',
        receivableReference: 'DUE-TEST',
        status: 'under_review',
        amount: 10000,
        currency: 'YER',
        propertyTitle: 'شقة اختبار المراجعة',
        hasProof: true,
      );

  @override
  Future<Response<List<int>>> paymentProof(
    int paymentId, {
    bool actingAsAgent = false,
  }) async {
    proofLoads++;
    return Response(
      requestOptions: RequestOptions(path: '/test-proof'),
      data: uxImage,
    );
  }

  @override
  Future<FinancialPayment> reviewPayment(
    int paymentId,
    String decision, {
    String? note,
    bool actingAsAgent = false,
  }) async {
    decisions.add((paymentId, decision, note, actingAsAgent));
    return FinancialPayment(
      id: paymentId,
      reference: 'PAY-TEST',
      status: 'correction_required',
      amount: 10000,
      currency: 'YER',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('financial balances preserve currency and read earlier YER summaries', () {
    final mixed = FinancialAccountSummary.fromJson({
      'pending_payouts': 20000,
      'amounts_by_currency': {
        'pending_payouts': {'YER': 20000, 'USD': 12.5},
        'open_platform_due': {'SAR': 6},
      },
    });
    expect(mixed.pendingPayouts, {'YER': 20000, 'USD': 12.5});
    expect(mixed.openPlatformDue, {'SAR': 6});
    expect(FinancialAccountSummary.fromJson({'paid_payouts': 25}).paidPayouts, {'YER': 25});
  });

  test('listing editor keeps monthly price and selected rental conditions before settlement', () {
    final source = File(
      'lib/features/properties/presentation/listing_editor_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final _monthlyRent = TextEditingController()'));
    expect(source, contains('final _rentalTermMonths = TextEditingController()'));
    expect(source, contains('final _advanceMonths = TextEditingController()'));
    expect(source, contains('الإيجار الشهري'));
    expect(source, contains('RentalConditionsEditor'));
    final conditions = File('lib/features/properties/presentation/rental_conditions_editor.dart').readAsStringSync();
    expect(conditions, contains('عدد أشهر المقدم'));
    expect(source, isNot(contains('مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.')));
    expect(source, contains("String _priceDisplayMode = 'excludes_sai'"));
  });

  test('published Sai consent clearly applies to a platform-sourced completed deal with explicit action', () {
    final source = File(
      'lib/features/properties/presentation/my_listings_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'ألتزم بسداد مستحق المنصة من السعي عند إتمام صفقة جاءت من عميل عبر المنصة، وفق نسبة المنصة الموضحة.',
      ),
    );
    expect(source, contains('إقرار السعي للإعلان المنشور'));
    expect(source, contains('أوافق على الإقرار'));
    expect(source, contains('financialRepositoryProvider).attestSai(item.id)'));
  });

  test('Financial V1 repository uses authoritative user and GM API routes', () {
    final source = File(
      'lib/features/financial/data/financial_repository.dart',
    ).readAsStringSync();

    expect(source, contains('/properties/\$propertyId/financial-config'));
    expect(source, contains('/finance/sai-attestations/pending'));
    expect(source, contains('/finance/payments/\$paymentId/proof'));
    expect(source, contains('/finance/receivables/\$receivableId/payments'));
    expect(source, contains('/admin/finance/payments/\$paymentId'));
    expect(source, contains('/admin/finance/payments/\$paymentId/review'));
    expect(source, contains('/admin/finance/summary'));
    expect(source, contains('/admin/finance/workspace'));
    expect(source, contains('/admin/finance/payment-methods'));
  });

  test('manual payment journey contains locked anti fraud and evidence steps', () {
    final source = File(
      'lib/features/financial/presentation/deal_financial_screen.dart',
    ).readAsStringSync();

    expect(source, contains('إتمام الدفع'));
    expect(source, contains('لا تحول إلى أي رقم آخر يرسله لك شخص عبر المحادثات'));
    expect(source, contains('بيانات الدفع المعتمدة تظهر في هذه الصفحة فقط'));
    expect(source, contains('نسخ الرقم'));
    expect(source, contains('نسخ المبلغ'));
    expect(source, contains('لقد أتممت التحويل'));
    expect(source, contains('إرسال للتحقق'));
    expect(source, contains('لا تدفع مرة أخرى لهذه العملية'));
  });

  test('wallet logos are bundled declared and mapped to their payment methods', () {
    expect(File('assets/payments/jeeb.png').existsSync(), isTrue);
    expect(File('assets/payments/kuraimi.png').existsSync(), isTrue);
    expect(File('assets/payments/jawali.png').existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final models = File(
      'lib/features/financial/domain/financial_models.dart',
    ).readAsStringSync();
    expect(pubspec, contains('assets/payments/'));
    expect(models, contains("'assets/payments/jeeb.png'"));
    expect(models, contains("'assets/payments/kuraimi.png'"));
    expect(models, contains("'assets/payments/jawali.png'"));
  });

  test('advertiser financial account includes deals payouts and platform receivables', () {
    final source = File(
      'lib/features/financial/presentation/financial_account_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ملخص الحساب'));
    expect(source, contains('مستحقات المنصة عليّ'));
    expect(source, contains('مستحق لي / التحويلات'));
    expect(source, contains('صفقاتي'));
    expect(source, contains('مدفوعاتي'));
    expect(source, contains('سداد مستحق المنصة'));
  });

  test('claimed payment tasks open the actor-bound review screen', () {
    final source = File(
      'lib/features/support/presentation/support_tasks_screen.dart',
    ).readAsStringSync();

    expect(source, contains("case 'payment_review':"));
    expect(source, contains('_paymentReviewDialog(task)'));
    expect(source, contains('builder: (_) => SupportPaymentReviewScreen('));
    expect(source, contains('paymentId: task.sourceId'));
    expect(source, contains('actingAsAgent: widget.actingAsAgent'));
  });

  testWidgets('receipt opens with zoom and correction requires a reason', (tester) async {
    await tester.runAsync(loadUxFixtures);
    final payments = _SupportPaymentRepository();
    final container = uxContainer(
      user: uxUser(roles: const ['support_agent']),
      extra: [financialRepositoryProvider.overrideWithValue(payments)],
    );
    await pumpUx(tester, container, Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<String>(MaterialPageRoute(
            builder: (_) => const SupportPaymentReviewScreen(
              paymentId: 21, actingAsAgent: true,
            ),
          )),
          child: const Text('فتح الاختبار'),
        ),
      ),
    ));
    await tester.tap(find.text('فتح الاختبار'));
    await uxFrames(tester);
    expect(find.textContaining('DUE-TEST'), findsOneWidget);
    final receipt = find.text('عرض الإيصال');
    await tester.ensureVisible(receipt);
    await tester.tap(receipt);
    await uxFrames(tester);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.pageBack();
    await uxFrames(tester);
    expect(payments.proofLoads, 1);
    await tester.tap(find.text('طلب تصحيح الإيصال'));
    await uxFrames(tester);
    final confirm = find.text('تأكيد');
    await tester.tap(confirm);
    await uxFrames(tester);
    expect(payments.decisions, isEmpty);
    await tester.enterText(find.byType(TextField), 'أرسل صورة أوضح');
    await uxFrames(tester);
    await tester.tap(confirm);
    await uxFrames(tester);
    expect(payments.decisions, [(21, 'correction', 'أرسل صورة أوضح', true)]);
    await closeUx(tester);
  });

  test('general manager finance workspace exposes complete sections and filters', () {
    final source = File(
      'lib/features/admin/presentation/general_manager_finance_screens.dart',
    ).readAsStringSync();
    final hubs = File(
      'lib/features/admin/presentation/general_manager_finance_hubs.dart',
    ).readAsStringSync();
    final operations = File(
      'lib/features/admin/presentation/general_manager_operations_screen.dart',
    ).readAsStringSync();

    expect(source, contains('إدارة طرق الدفع'));
    expect(source, contains('السماح بالدفع الكامل للصفقة'));
    expect(source, contains('السماح بالسعي / مستحقات المنصة فقط'));
    expect(source, contains('الصفقات والمعاملات'));
    expect(source, contains('المدفوعات الواردة'));
    expect(source, contains('التحويلات للمعلنين'));
    expect(source, contains('مستحقات المنصة'));
    expect(source, contains('المتأخر بعد 24 ساعة'));
    expect(source, contains('القيود المالية'));
    expect(source, contains('الاستردادات'));
    expect(source, contains('النزاعات'));
    expect(source, contains('سجل التدقيق المالي'));
    expect(source, contains("labelText: 'الفترة'"));
    expect(source, contains("labelText: 'نوع الصفقة'"));
    expect(source, contains("labelText: 'نوع المعلن'"));
    expect(source, contains("labelText: 'المحافظة'"));
    expect(hubs, contains('GeneralManagerAdministrationFinancialHubScreen'));
    expect(hubs, contains('const GeneralManagerPaymentMethodsScreen()'));
    for (final section in ['home', 'reports']) {
      final actions = operations
          .split('case GeneralManagerSection.$section:')[1]
          .split('case GeneralManagerSection.')[0];
      expect(actions, contains('const GeneralManagerFinanceWorkspaceScreen()'));
    }
  });
}
