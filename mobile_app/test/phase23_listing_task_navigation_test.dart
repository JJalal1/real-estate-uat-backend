import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/reviews/data/listing_review_repository.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_duplicate_candidate.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_review_models.dart';
import 'package:real_estate_mobile/features/support/data/support_workspace_repository.dart';
import 'package:real_estate_mobile/features/support/domain/support_workspace_models.dart';
import 'package:real_estate_mobile/features/support/presentation/support_tasks_screen.dart';

class _Actor extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
        'id': 6,
        'name': 'Synthetic support actor',
        'account_status': 'active',
        'roles': ['support_agent'],
        'permissions': ['listings.moderate', 'support.handle_reports'],
      });

  void changeAccount() {
    state = AsyncData(AuthUser.fromJson({
      'id': 26,
      'name': 'Other synthetic actor',
      'account_status': 'active',
      'roles': ['registered_user'],
    }));
  }
}

class _Tasks implements SupportWorkspaceRepository {
  bool completed = false;
  int loads = 0;
  @override
  Future<List<SupportTaskItem>> tasks({
    String scope = 'inbox',
    String? type,
    String? status,
    String? priority,
    String? severity,
    int? assigneeId,
    DateTime? createdFrom,
    DateTime? createdTo,
    bool overdue = false,
    bool actingAsAgent = false,
  }) async {
    loads++;
    if (completed) return [];
    return [
        SupportTaskItem.fromJson({
          'id': 700,
          'source_type': 'listing_review',
          'source_id': 106,
          'subject': 'Owned listing verification task',
          'status': 'in_progress',
          'priority': 'normal',
          'is_mine': true,
          'can_claim': false,
          'is_overdue': false,
        }),
      ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Reviews implements ListingReviewRepository {
  final requestedIds = <int>[];
  Completer<(ReviewListingDetail, List<ListingDuplicateCandidate>)>? pending;

  (ReviewListingDetail, List<ListingDuplicateCandidate>) result(int id) => (
        ReviewListingDetail.fromJson({
          'id': id,
          'title': 'Private case for listing $id',
          'purpose': 'rent',
          'type': 'apartment',
          'price': 175000,
          'review_status': 'under_review',
          'owner': {'name': 'Synthetic publisher'},
          'latitude': 15.3694,
          'longitude': 44.191,
          'review_history': [
            {'action': 'submitted', 'actor_name': 'Synthetic publisher'},
            {'action': 'review_started', 'actor_name': 'Synthetic reviewer'},
          ],
        }),
        <ListingDuplicateCandidate>[],
      );

  @override
  Future<(ReviewListingDetail, List<ListingDuplicateCandidate>)> evidence(
      int id) async {
    requestedIds.add(id);
    if (pending != null) return pending!.future;
    return result(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

Future<ProviderContainer> _openTasks(
    WidgetTester tester, _Reviews reviews, {_Tasks? tasks}) async {
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_Actor.new),
    supportWorkspaceRepositoryProvider.overrideWithValue(tasks ?? _Tasks()),
    listingReviewRepositoryProvider.overrideWithValue(reviews),
  ]);
  await container.read(authControllerProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light,
      home: const SupportTasksScreen(initialScope: 'mine'),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('owned task opens its exact case and refreshes after returning',
      (tester) async {
    final reviews = _Reviews();
    final tasks = _Tasks();
    final container = await _openTasks(tester, reviews, tasks: tasks);
    addTearDown(container.dispose);
    await tester.ensureVisible(find.text('فتح'));
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(reviews.requestedIds, [106]);
    expect(find.text('Private case for listing 106'), findsOneWidget);
    expect(find.text('شقة'), findsOneWidget);
    expect(find.text('apartment'), findsNothing);
    expect(find.text('طلبات التحقيق'), findsNothing);
    await tester.scrollUntilVisible(find.text('أُرسل للمراجعة'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('أُرسل للمراجعة'), findsOneWidget);
    expect(find.text('submitted'), findsNothing);
    expect(find.text('review_started'), findsNothing);
    tasks.completed = true;
    Navigator.of(tester.element(find.text('أُرسل للمراجعة'))).pop(true);
    await tester.pumpAndSettle();
    expect(tasks.loads, 2);
    expect(find.text('Owned listing verification task'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late private case response cannot cross an account switch',
      (tester) async {
    final reviews = _Reviews()
      ..pending =
          Completer<(ReviewListingDetail, List<ListingDuplicateCandidate>)>();
    final container = await _openTasks(tester, reviews);
    addTearDown(container.dispose);
    await tester.ensureVisible(find.text('فتح'));
    await tester.tap(find.text('فتح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(reviews.requestedIds, [106]);
    (container.read(authControllerProvider.notifier) as _Actor).changeAccount();
    reviews.pending!.complete(reviews.result(106));
    await tester.pumpAndSettle();
    expect(find.text('Private case for listing 106'), findsNothing);
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
