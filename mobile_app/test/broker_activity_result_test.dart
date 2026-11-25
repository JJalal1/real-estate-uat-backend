import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';

import 'broker_experience_ui_test.dart'
    show BrokerTestAuth, BrokerTestRepository;

class _ActivityRepository extends BrokerTestRepository {
  int activityRequests = 0;

  @override
  Future<BrokerPage<BrokerDeal>> activity({int? threadId, int page = 1}) async {
    activityRequests++;
    return BrokerPage(
        items: [for (var id = 1; id <= 14; id++) _deal(id)],
        page: page,
        lastPage: 1);
  }

  @override
  Future<BrokerDeal> deal(int id) async => _deal(id);

  BrokerDeal _deal(int id) => BrokerDeal.fromJson({
        'id': id,
        'advertiser_id': 1,
        'property_title': 'العقار $id',
        'customer_name': 'الطرف الآخر $id',
        'advertiser_name': 'المعلن',
        'status': 'confirmed',
        'basis_amount': '82000',
        'currency': 'YER',
        'advertiser_view_revision': 4,
        if (id != 1) ...{
          'listing_price': '100000',
          'listing_currency': 'SAR',
          'sai_amount': 1640,
          'sai_currency': 'YER',
          'sai_rate_percent': 2,
          'sai_payment_status': 'confirmed',
          'confirmed_at': '2026-10-13T12:00:00Z',
        },
      });
}

Future<void> _openActivity(
    WidgetTester tester, _ActivityRepository repository) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(BrokerTestAuth.new),
      brokerRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: BrokerActivityScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const dialogKey = ValueKey('broker-deal-result-dialog');

  testWidgets(
      'activity opens the selected result in a modal and retains list position',
      (tester) async {
    final repository = _ActivityRepository();
    await _openActivity(tester, repository);
    expect(find.text('نشاطي'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('المحادثات'), findsNothing);

    final list = find.byKey(const ValueKey('broker-activity-deals'));
    final scrollable =
        find.descendant(of: list, matching: find.byType(Scrollable));
    final card = find.byKey(const ValueKey(8));
    final show = find.descendant(of: card, matching: find.text('عرض النتيجة'));
    await tester.scrollUntilVisible(show, 300, scrollable: scrollable);
    await tester.ensureVisible(show);
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scrollable).position;
    final offset = position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(show);
    await tester.pumpAndSettle();
    final dialog = find.byKey(dialogKey);
    expect(dialog, findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    Finder inResult(String label) =>
        find.descendant(of: dialog, matching: find.text(label));
    expect(inResult('العقار 8'), findsOneWidget);
    expect(inResult('الطرف الآخر 8'), findsOneWidget);
    expect(inResult('صفقة مؤكدة'), findsOneWidget);
    expect(inResult('سعر الإعلان'), findsOneWidget);
    expect(inResult('100,000 SAR'), findsOneWidget);
    expect(inResult('السعر المتفق عليه'), findsOneWidget);
    expect(inResult('82,000 ر.ي'), findsOneWidget);
    expect(inResult('1,640 ر.ي'), findsOneWidget);
    expect(inResult('2%'), findsOneWidget);
    expect(inResult('تم تأكيد الدفع'), findsOneWidget);
    expect(inResult('تاريخ التأكيد'), findsOneWidget);
    expect(repository.seenDeals, [(8, 4)]);

    await tester.tap(inResult('إغلاق'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(position.pixels, offset);
    expect(repository.activityRequests, 1);
  });

  testWidgets(
      'a legacy outcome labels missing listing price without inventing Sai',
      (tester) async {
    await _openActivity(tester, _ActivityRepository());
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey(1)), matching: find.text('عرض النتيجة')));
    await tester.pumpAndSettle();

    final result = find.byKey(dialogKey);
    expect(find.descendant(of: result, matching: find.text('غير مسجل')),
        findsOneWidget);
    expect(find.text('مبلغ السعي'), findsNothing);
    expect(find.text('حالة دفع السعي'), findsNothing);
    expect(find.text('تاريخ التأكيد'), findsNothing);
  });
}
