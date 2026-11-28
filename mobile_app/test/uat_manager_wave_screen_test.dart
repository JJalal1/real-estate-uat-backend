import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_gate.dart';
import 'package:real_estate_mobile/features/admin/data/general_manager_repository.dart';
import 'package:real_estate_mobile/features/admin/domain/general_manager_insights.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_operations_screen.dart';
import 'package:real_estate_mobile/features/financial/data/financial_repository.dart';
import 'package:real_estate_mobile/features/support/data/support_workspace_repository.dart';
import 'package:real_estate_mobile/features/support/domain/support_workspace_models.dart';
import 'package:real_estate_mobile/features/support/presentation/support_workspace_pages.dart';

import 'support/owner_ux_fixtures.dart' show UxAuth, uxUser;

class _ExecutiveResults extends Fake implements GeneralManagerRepository {
  final periods = <String>[];

  @override
  Future<GeneralManagerOperations> operations(String period,
      {int? governorateId}) async {
    periods.add(period);
    return const GeneralManagerOperations(
      [
        ExecutiveTeamStats({
          'id': 1,
          'name': 'فريق المحافظة',
          'governorate_id': 2,
          'members': 2,
          'received': 5,
          'completed': 2,
          'overdue': 3,
          'published': 1,
        })
      ],
      {'received': 5, 'completed': 2, 'published': 1},
      {},
      0,
      0,
    );
  }
}

class _Finance extends Fake implements FinancialRepository {
  @override
  Future<Map<String, dynamic>> adminSummary({
    String period = '30d',
    int? governorateId,
    String? transactionType,
    String? advertiserType,
  }) async =>
      {'payments_waiting_review': 0};
}

class _TeamMembers extends Fake implements SupportWorkspaceRepository {
  final periods = <String>[];

  SupportTeamMember _worker(int completed) => SupportTeamMember.fromJson({
        'id': 212,
        'name': 'عضو الفريق',
        'role': 'support_agent',
        'team_id': 75,
        'team_name': 'فريق المحافظة',
        'open_tasks': 3,
        'completed_in_period': completed,
      });

  @override
  Future<List<SupportTeamMember>> team() async => [_worker(1)];

  @override
  Future<List<SupportTeamSummary>> teams() async => throw StateError(
      'The member workspace must not request the team directory.');

  @override
  Future<List<SupportTeamMember>> teamActivity({String? period}) async {
    periods.add(period!);
    return [_worker(8)];
  }
}

void main() {
  testWidgets(
      'executive home treats ordinary overdue work as monitoring, not a decision',
      (tester) async {
    final results = _ExecutiveResults();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          generalManagerRepositoryProvider.overrideWithValue(results),
          financialRepositoryProvider.overrideWithValue(_Finance()),
        ],
        child: const MaterialApp(
            home: GeneralManagerOperationsScreen(GeneralManagerSection.home))));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد حالات بانتظار قرارك'), findsOneWidget);
    expect(find.text('عرض الحالات'), findsNothing);
    expect(find.byTooltip('الرسائل'), findsOneWidget);

    await tester.tap(find.text('اليوم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('٧ أيام'));
    await tester.pumpAndSettle();
    expect(results.periods, ['day', '7d']);
    expect(find.text('مؤشرات الفترة'), findsOneWidget);
  });

  testWidgets(
      'regional supervisor opens an individual member and can change the activity period',
      (tester) async {
    final team = _TeamMembers();
    final actor = uxUser(id: 91, roles: ['support_manager']);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => UxAuth(actor)),
          supportWorkspaceRepositoryProvider.overrideWithValue(team),
        ],
        child: const MaterialApp(
            home: Stage6AuthGate(child: SupportTeamScreen()))));
    await tester.pumpAndSettle();

    expect(find.text('أعضاء فريقي'), findsOneWidget);
    expect(find.byTooltip('مراسلة عضو الفريق'), findsOneWidget);
    expect(find.byTooltip('فرق المحافظات'), findsNothing);
    await tester.tap(find.text('عضو الفريق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('٧ أيام'));
    await tester.pumpAndSettle();
    expect(team.periods, ['7d']);
    expect(find.text('المهام المنجزة في الفترة'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets(
      'staff account exposes work notifications and hides consumer actions',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider
          .overrideWith(() => UxAuth(uxUser(roles: ['support_agent']))),
    ], child: const MaterialApp(home: AccountScreen())));
    await tester.pumpAndSettle();

    expect(find.text('إشعارات العمل'), findsOneWidget);
    expect(find.text('البحث الذكي'), findsNothing);
    expect(find.text('شوهد مؤخرًا'), findsNothing);
    expect(find.text('مدفوعاتي'), findsNothing);
    expect(find.text('تفضيلات الإشعارات'), findsNothing);
  });
}
