import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_connections_screen.dart';

class _BrokerAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
        'id': 1,
        'name': 'دلال الاختبار',
        'account_status': 'active',
      });
}

class _Inbox extends Fake implements BrokerRepository {
  _Inbox(this.sevenDaysAgo, this.eightDaysAgo);

  final DateTime sevenDaysAgo;
  final DateTime eightDaysAgo;
  final requests = <(String?, bool)>[];
  final readThreads = <int>{};

  @override
  Future<BrokerPage<BrokerCustomer>> customers({
    String? stage,
    int? propertyId,
    int page = 1,
    String? filter,
    bool includeOtherThreads = false,
  }) async {
    requests.add((stage, includeOtherThreads));
    final rows = [
      {
        'thread_id': 19,
        'customer_name': 'سامية الاختبار',
        'property_id': 7,
        'property_title': 'وصف العقار المخفي',
        'stage': 'appointment_set',
        'last_message_preview': 'أرسلت لك\nتفاصيل المكتب',
        'last_message_is_mine': true,
        'last_message_at': sevenDaysAgo.toIso8601String(),
        'unread_count': 0,
        'followup': {'private_note': 'ملاحظة خاصة'},
      },
      {
        'thread_id': 20,
        'customer_name': 'سامية الاختبار',
        'property_id': 8,
        'stage': 'reserved',
        'last_message_preview': 'هل الشقة ما زالت متاحة؟',
        'last_message_at': eightDaysAgo.toIso8601String(),
        'unread_count': readThreads.contains(20) ? 0 : 3,
      },
      if (includeOtherThreads)
        {
          'thread_id': 21,
          'customer_name': 'صالح الاختبار',
          'stage': 'unclassified',
          'last_message_preview': 'تواصل مباشر',
        },
    ];
    return BrokerPage(
      items: rows
          .where((row) => stage == null || row['stage'] == stage)
          .map(BrokerCustomer.fromJson)
          .toList(),
      page: 1,
      lastPage: 1,
    );
  }
}

const _weekdays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

Finder _card(int id) => find.byKey(ValueKey('broker-customer-$id'));
Finder _chip(String stage) =>
    find.byKey(ValueKey('broker-message-filter-$stage'));

void main() {
  for (final dark in [false, true]) {
    testWidgets('broker message cards and status filters work in dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final seven = DateTime(now.year, now.month, now.day - 7, 12);
      final eight = DateTime(now.year, now.month, now.day - 8, 12);
      final inbox = _Inbox(seven, eight);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const BrokerConnectionsScreen()),
        GoRoute(
            path: '/messages/:id',
            builder: (_, state) {
              final id = int.parse(state.pathParameters['id']!);
              inbox.readThreads.add(id);
              return Scaffold(body: Text('conversation-$id'));
            }),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_BrokerAuth.new),
            brokerRepositoryProvider.overrideWithValue(inbox),
          ],
          child: MaterialApp.router(
            theme: dark ? AppTheme.dark : AppTheme.light,
            routerConfig: router,
          )));
      await tester.pumpAndSettle();

      expect(inbox.requests.single, (null, true));
      expect(find.text('الرسائل'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      for (final label in [
        'المتابعة',
        'المحادثات',
        'الكل',
        'تحتاج ردك',
        'حان الموعد',
        'الحالة',
        'وصف العقار المخفي',
        'تصنيف العميل',
        'آخر تواصل',
        'ملاحظة خاصة'
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.widget<ChoiceChip>(_chip('all')).selected, isTrue);
      expect(tester.getCenter(_chip('all')).dx,
          greaterThan(tester.getCenter(_chip('appointment_set')).dx));
      expect(tester.getCenter(_chip('appointment_set')).dx,
          greaterThan(tester.getCenter(_chip('unclassified')).dx));
      expect(tester.getTopLeft(_card(19)).dy,
          lessThan(tester.getTopLeft(_card(20)).dy));
      expect(tester.getTopLeft(_card(20)).dy,
          lessThan(tester.getTopLeft(_card(21)).dy));

      final outgoing = find.text('أنت: أرسلت لك تفاصيل المكتب');
      final incoming = find.text('هل الشقة ما زالت متاحة؟');
      final recent = find.text(_weekdays[seven.weekday - 1]);
      final absolute = find.text(
          '${eight.year}/${eight.month.toString().padLeft(2, '0')}/${eight.day.toString().padLeft(2, '0')}');
      expect(outgoing, findsOneWidget);
      expect(incoming, findsOneWidget);
      expect(recent, findsOneWidget);
      expect(absolute, findsOneWidget);
      expect(
          tester.getCenter(recent).dx, lessThan(tester.getCenter(outgoing).dx));
      expect(tester.widget<Text>(outgoing).maxLines, 1);
      expect(tester.widget<Text>(outgoing).overflow, TextOverflow.ellipsis);
      final badge = find.byKey(const ValueKey('broker-message-unread-20'));
      expect(
          tester.widget<Badge>(badge).backgroundColor, const Color(0xffb91c1c));
      expect(
          find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('broker-message-unread-19')), findsNothing);

      await tester.tap(find.descendant(
          of: _card(19), matching: find.text('سامية الاختبار')));
      await tester.pumpAndSettle();
      expect(find.text('conversation-19'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(outgoing);
      await tester.pumpAndSettle();
      expect(find.text('conversation-19'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      final bounds = tester.getRect(_card(20));
      await tester
          .tapAt(Offset(bounds.left + bounds.width / 2, bounds.top + 12));
      await tester.pumpAndSettle();
      expect(find.text('conversation-20'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(badge, findsNothing);

      await tester.tap(_chip('appointment_set'));
      await tester.pumpAndSettle();
      expect(inbox.requests.last, ('appointment_set', true));
      expect(_card(19), findsOneWidget);
      expect(_card(20), findsNothing);
      await tester.ensureVisible(_chip('unclassified'));
      await tester.tap(_chip('unclassified'));
      await tester.pumpAndSettle();
      expect(inbox.requests.last, ('unclassified', true));
      expect(_card(21), findsOneWidget);
      await tester.tap(find.text('تواصل مباشر'));
      await tester.pumpAndSettle();
      expect(find.text('conversation-21'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
