import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';
import 'package:real_estate_mobile/features/financial/data/financial_repository.dart';
import 'broker_experience_ui_test.dart' show BrokerTestRepository;

class _Broker extends BrokerTestRepository {
  int attempts = 0;
  final amounts = <double?>[];
  @override
  Future<BrokerDeal> reportDeal(int threadId, {double? amount}) async {
    attempts++; amounts.add(amount);
    if (attempts == 1) {
      final options = RequestOptions(path: '/broker/customers/$threadId/completed-deal');
      throw DioException(requestOptions: options, type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 409, data: {
          'code': 'sai_consent_required', 'data': {'property_id': 11, 'sai_term_id': 7,
            'text': 'السعي المحفوظ لهذه المحادثة 50%. ألتزم بمستحق المنصة 20% من السعي عند إتمام الصفقة.'},
        }));
    }
    return deal(4);
  }
}
class _Finance implements FinancialRepository {
  final receipts = <(int, int?)>[];
  @override
  Future<void> attestSai(int propertyId, {int? saiTermId}) async { receipts.add((propertyId, saiTermId)); }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  for (final accepts in [false, true]) {
    testWidgets('completion asks for its exact frozen Sai terms; explicit acceptance=$accepts', (tester) async {
      final broker = _Broker(), finance = _Finance();
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(body: Consumer(builder: (context, ref, _) =>
          TextButton(onPressed: () => reportBrokerDeal(context, ref, 19), child: const Text('تسجيل النتيجة'))))),
        GoRoute(path: '/broker/deals/:id', builder: (_, state) => Scaffold(body: Text('النتيجة ${state.pathParameters['id']}'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [brokerRepositoryProvider.overrideWithValue(broker),
        financialRepositoryProvider.overrideWithValue(finance)], child: MaterialApp.router(routerConfig: router)));
      await tester.tap(find.text('تسجيل النتيجة')); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '110000');
      await tester.tap(find.text('إرسال للتأكيد')); await tester.pumpAndSettle();
      expect(find.text('إقرار السعي لهذه المحادثة'), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(finance.receipts, isEmpty); expect(broker.attempts, 1);
      await tester.tap(find.text(accepts ? 'أوافق وأتابع' : 'ليس الآن')); await tester.pumpAndSettle();
      expect(finance.receipts, accepts ? [(11, 7)] : isEmpty);
      expect(broker.attempts, accepts ? 2 : 1);
      expect(broker.amounts, accepts ? [110000.0, 110000.0] : [110000.0]);
      expect(find.text('النتيجة 4'), accepts ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
