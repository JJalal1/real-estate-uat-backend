import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';
import 'package:real_estate_mobile/features/financial/data/financial_repository.dart';
import 'package:real_estate_mobile/features/financial/domain/financial_models.dart';

import 'broker_experience_ui_test.dart' show BrokerTestRepository;
import 'support/owner_ux_fixtures.dart';

const _methods = [
  FinancialPaymentMethod(
    id: 41,
    key: 'transfer',
    name: 'حوالة',
    beneficiaryName: 'مستفيد الحوالة',
    destinationLabel: 'رقم الحوالة',
    destinationValue: '410002',
    currency: 'YER',
    available: true,
  ),
  FinancialPaymentMethod(
    id: 31,
    key: 'jawali',
    name: 'جوالي',
    beneficiaryName: 'مستفيد جوالي',
    destinationLabel: 'رقم المحفظة',
    destinationValue: '310002',
    currency: 'YER',
    available: true,
  ),
  FinancialPaymentMethod(
    id: 21,
    key: 'kuraimi',
    name: 'الكريمي',
    beneficiaryName: 'مستفيد الكريمي',
    destinationLabel: 'رقم المحفظة',
    destinationValue: '210002',
    currency: 'YER',
    available: true,
  ),
  FinancialPaymentMethod(
    id: 11,
    key: 'jeeb',
    name: 'جيب',
    beneficiaryName: 'مستفيد جيب',
    destinationLabel: 'رقم المحفظة',
    destinationValue: '110002',
    currency: 'YER',
    available: true,
  ),
];

class _Dues extends BrokerTestRepository {
  _Dues(this.type);
  final String type;
  String status = 'open';
  double get amount => type == 'rent' ? 32000 : 769000;

  @override
  Future<BrokerPage<BrokerDeal>> activity({int? threadId, int page = 1}) async {
    final deal = BrokerDeal.fromJson({
      'id': 100,
      'advertiser_id': 1,
      'customer_name': 'عميل تجريبي',
      'property_title': 'عقار اختبار السداد',
      'status': 'confirmed',
      'transaction_type': type,
      'basis_amount': 320000,
      'currency': 'YER',
      'platform_due_status': switch (status) {
        'paid' => 'paid',
        'under_review' => 'pending_review',
        _ => 'pending_payment',
      },
    });
    return BrokerPage(items: [deal, deal], page: 1, lastPage: 1);
  }

  @override
  Future<Map<String, dynamic>> finance() async => {
        'balances': [
          {
            'currency': 'YER',
            'open': status == 'paid' ? 0 : amount,
            'paid': status == 'paid' ? amount + 100 : 100,
          }
        ],
        'receivables': [
          {
            'id': 8,
            'reference': 'DUE-SYNTHETIC',
            'property_title': 'عقار اختبار السداد',
            'transaction_type': type,
            'basis_amount': 192250000,
            'monthly_basis_amount': 320000,
            'sai_amount': 100000,
            'amount_total': amount,
            'remaining_amount': status == 'paid' ? 0 : amount,
            'status': status,
            'due_at': '2026-11-26T14:15:00Z',
            'currency': 'YER',
          },
          {
            'id': 3,
            'reference': 'DUE-OLD',
            'property_title': 'مستحق مسدد سابقًا',
            'transaction_type': 'sale',
            'remaining_amount': 0,
            'status': 'paid',
            'currency': 'YER',
          },
        ],
      };
}

class _Payments implements FinancialRepository {
  _Payments(this.dues);
  final _Dues dues;
  final selectedMethods = <int>[];
  final submissions = <(int, String, String?, String?, String?)>[];
  var failUploadOnce = true;

  @override
  Future<FinancialDeal> receivableDeal(int receivableId) async => FinancialDeal(
        id: 4,
        agreementId: 0,
        propertyId: 7,
        propertyTitle: 'عقار اختبار السداد',
        transactionType: dues.type,
        currency: 'YER',
        baseAmount: 192250000,
        saiPayer: 'advertiser',
        saiTotalAmount: 100000,
        canPayFull: false,
        canPaySaiOnly: false,
        requiredFullPayment: 0,
        requiredSaiPayment: dues.amount,
        paymentMethods: _methods,
        payments: const [],
        receivable: {
          'status': dues.status,
          'remaining_amount': dues.amount,
          'currency': 'YER'
        },
      );

  @override
  Future<FinancialPayment> createReceivablePayment({
    required int receivableId,
    required int paymentMethodId,
  }) async {
    expect(receivableId, 8);
    selectedMethods.add(paymentMethodId);
    return FinancialPayment(
        id: paymentMethodId + 100,
        reference: 'TEST',
        status: 'waiting_payment',
        amount: dues.amount,
        currency: 'YER',
        method: _methods.singleWhere((method) => method.id == paymentMethodId));
  }

  @override
  Future<FinancialPayment> submitProof({
    required int paymentId,
    required String imagePath,
    String? senderName,
    String? senderPhone,
    String? providerReference,
  }) async {
    submissions.add(
        (paymentId, imagePath, senderName, senderPhone, providerReference));
    if (failUploadOnce) {
      failUploadOnce = false;
      throw StateError('Synthetic transfer error');
    }
    dues.status = 'under_review';
    return FinancialPayment(
        id: paymentId,
        reference: 'TEST',
        status: 'proof_submitted',
        amount: dues.amount,
        currency: 'YER',
        hasProof: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('activity confirms a settled deal exactly once on the next read',
      (tester) async {
    final dues = _Dues('rent')..status = 'under_review';
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
      brokerRepositoryProvider.overrideWithValue(dues),
    ]);
    await pumpUx(tester, scope, const Scaffold(body: BrokerDealsList()));
    await tester.pumpAndSettle();
    expect(find.textContaining('إثبات السداد قيد التحقق'), findsOneWidget);
    expect(find.textContaining('صفقة مؤكدة'), findsNothing);
    dues.status = 'paid';
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('صفقة مؤكدة'), findsOneWidget);
    expect(find.text('عقار اختبار السداد'), findsOneWidget);
    expect(find.text('الإيجار الشهري: 320000.00 ر.ي'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  for (final type in ['sale', 'rent']) {
    testWidgets(
      'platform dues $type selects real method, copies only its values and submits receipt',
      (tester) async {
        const media = MethodChannel('real_estate/media');
        const payment = ValueKey('receivable-method-jeeb');
        final clipboard = <String>[];
        final removedFiles = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        messenger.setMockMethodCallHandler(media, (call) async {
          if (call.method == 'pickImages') {
            return ['/tmp/receipt-selected.jpg', '/tmp/receipt-discarded.jpg'];
          }
          if (call.method == 'clearTemporaryFiles') {
            removedFiles.addAll(
                ((call.arguments as Map)['paths'] as List).cast<String>());
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(media, null);
        });

        final dues = _Dues(type);
        final payments = _Payments(dues);
        final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
          brokerRepositoryProvider.overrideWithValue(dues),
          financialRepositoryProvider.overrideWithValue(payments),
        ]);
        await pumpUx(tester, scope, const BrokerFinanceScreen());
        await tester.pumpAndSettle();

        expect(find.text('مستحق مسدد سابقًا'), findsNothing);
        expect(find.textContaining('متأخر السداد'), findsNothing);
        expect(find.textContaining('أساس الحساب'), findsNothing);
        expect(
            find.text(
                'إذا لم يتم السداد خلال ٢٤ ساعة من بيع العقار أو تأجيره، سيتم إيقاف الحساب.'),
            findsOneWidget);
        expect(find.textContaining('آخر مهلة للسداد'), findsOneWidget);
        expect(
            find.text(type == 'rent'
                ? 'الإيجار الشهري: 320000.00 ر.ي'
                : 'إجمالي سعر العقار: 192250000.00 ر.ي'),
            findsOneWidget);

        await tester.tap(find.text('سداد مستحقات المنصة'));
        await tester.pumpAndSettle();
        final displayedMethods =
            tester.widgetList<ListTile>(find.byType(ListTile)).toList();
        expect(
            displayedMethods.map((tile) => tile.key),
            orderedEquals([
              payment,
              const ValueKey('receivable-method-kuraimi'),
              const ValueKey('receivable-method-jawali'),
              const ValueKey('receivable-method-transfer'),
            ]));
        final transfer =
            find.byKey(const ValueKey('receivable-method-transfer'));
        expect(
            find.descendant(
                of: transfer,
                matching: find.byIcon(Icons.compare_arrows_rounded)),
            findsOneWidget);

        for (final method in _methods.where((method) => method.key != 'jeeb')) {
          await tester
              .tap(find.byKey(ValueKey('receivable-method-${method.key}')));
          await tester.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          expect(find.descendant(of: dialog, matching: find.text(method.name)),
              findsOneWidget);
          expect(
              find.text('المستفيد: ${method.beneficiaryName}'), findsOneWidget);
          expect(
              find.text(
                  '${method.destinationLabel}: ${method.destinationValue}'),
              findsOneWidget);
          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(payment));
        await tester.pumpAndSettle();
        expect(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.text('جيب')),
            findsOneWidget);
        expect(find.text('المستفيد: مستفيد جيب'), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byIcon(Icons.content_copy_outlined)),
            findsNWidgets(3));
        final amount = dues.amount.toStringAsFixed(0);
        for (final tooltip in ['نسخ اسم المستفيد', 'نسخ الرقم', 'نسخ المبلغ']) {
          expect(find.text(tooltip), findsNothing);
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
        }
        expect(clipboard, ['مستفيد جيب', '110002', amount]);

        await tester.tap(find.text('لقد أتممت التحويل'));
        await tester.pumpAndSettle();
        final proof = find.byType(AlertDialog);
        expect(find.descendant(of: proof, matching: find.text('$amount YER')),
            findsOneWidget);
        expect(find.descendant(of: proof, matching: find.byType(TextField)),
            findsNothing);
        final send = find.text('إرسال للتحقق');
        await tester.tap(find.text('رفع صورة الاثبات(الايصال)'));
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(find.text('إرسال إثبات السداد'), findsOneWidget);
        expect(find.text('تم اختيار صورة الإثبات'), findsOneWidget);
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(payments.selectedMethods, [41, 31, 21, 11]);
        expect(
            payments.submissions,
            List.filled(
                2, (111, '/tmp/receipt-selected.jpg', null, null, null)));
        expect(removedFiles,
            ['/tmp/receipt-discarded.jpg', '/tmp/receipt-selected.jpg']);
        expect(find.text('عقار اختبار السداد'), findsOneWidget);
        expect(find.text('إثبات السداد قيد التحقق'), findsOneWidget);
        expect(find.text('سداد مستحقات المنصة'), findsNothing);

        dues.status = 'paid';
        scope.invalidate(brokerFinanceProvider);
        await tester.pumpAndSettle();
        expect(find.text('عقار اختبار السداد'), findsNothing);
        expect(find.text('المستحق: 0.00 ر.ي'), findsOneWidget);
        expect(
            find.text('المدفوع: ${(dues.amount + 100).toStringAsFixed(2)} ر.ي'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeUx(tester);
      },
    );
  }
}
