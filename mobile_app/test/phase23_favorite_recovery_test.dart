import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_favorite_status.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic $id', 'account_status': 'active',
  'phone_verified_at': '2026-11-11T00:00:00Z',
});

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(26);
  void change(int id) => state = AsyncData(_user(id));
}

class _Favorites implements FavoritesRepository {
  _Favorites(this.actor, this.read, this.mutations);
  final int actor;
  final Future<Set<int>> Function(int) read;
  final List<String> mutations;
  @override
  Future<Set<int>> favoriteIds() => read(actor);
  @override
  Future<void> add(int id) async { mutations.add('add:$actor:$id'); }
  @override
  Future<void> remove(int id) async { mutations.add('remove:$actor:$id'); }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _show(WidgetTester tester, _Auth auth,
    Future<Set<int>> Function(int) read, List<String> mutations) async {
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => auth),
    favoritesRepositoryProvider.overrideWith((ref) => _Favorites(
      ref.watch(authControllerProvider).asData?.value?.id ?? 0, read, mutations)),
  ], child: const MaterialApp(home: Scaffold(body: PropertyFavoriteAction(propertyId: 106)))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed favorite lookup retries without a false add or remove', (tester) async {
    var reads = 0;
    final recovery = Completer<Set<int>>();
    final mutations = <String>[];
    await _show(tester, _Auth(), (_) {
      reads++;
      if (reads == 1) return Future.error(StateError('offline'));
      return recovery.future;
    }, mutations);
    expect(find.byTooltip('إعادة تحميل المفضلة'), findsOneWidget);
    expect(find.byTooltip('حفظ في المفضلة'), findsNothing);
    expect(find.byTooltip('إزالة من المفضلة'), findsNothing);
    await tester.tap(find.byTooltip('إعادة تحميل المفضلة'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(mutations, isEmpty);
    final waiting = tester.widget<IconButton>(find.byTooltip('جارٍ تحميل المفضلة'));
    expect(waiting.onPressed, isNull);
    recovery.complete({106});
    await tester.pumpAndSettle();
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
    expect(mutations, isEmpty);
  });

  testWidgets('late favorite data from the previous actor cannot mark the next account', (tester) async {
    final auth = _Auth();
    final old = Completer<Set<int>>();
    final mutations = <String>[];
    await _show(tester, auth, (actor) => actor == 26 ? old.future : Future.value(<int>{}), mutations);
    expect(find.byTooltip('جارٍ تحميل المفضلة'), findsOneWidget);
    auth.change(28);
    await tester.pumpAndSettle();
    expect(find.byTooltip('حفظ في المفضلة'), findsOneWidget);
    old.complete({106});
    await tester.pumpAndSettle();
    expect(find.byTooltip('حفظ في المفضلة'), findsOneWidget);
    expect(find.byTooltip('إزالة من المفضلة'), findsNothing);
    expect(mutations, isEmpty);
  });

  test('unknown favorite status never becomes an unsaved state', () {
    final failure = PropertyFavoriteStatus.fromAsync(AsyncError<Set<int>>(StateError('offline'), StackTrace.empty), 106);
    expect(failure.failed, isTrue);
    expect(failure.tooltip, 'إعادة تحميل المفضلة');
    expect(PropertyFavoriteStatus.fromAsync(const AsyncLoading<Set<int>>(), 106).loading, isTrue);
    expect(PropertyFavoriteStatus.fromAsync(const AsyncData<Set<int>>({106}), 106).selected, isTrue);
    expect(PropertyFavoriteStatus.fromAsync(const AsyncData<Set<int>>({}), 106).selected, isFalse);
    expect(PropertyFavoriteStatus.fromAsync(null, 106).tooltip, 'حفظ في المفضلة');
  });
}
