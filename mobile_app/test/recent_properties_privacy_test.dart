import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'حساب اصطناعي', 'account_status': 'active'});
PropertySummary _property(int id, {String status = 'published'}) => PropertySummary.fromJson({
  'id': id, 'title': 'عقار اصطناعي $id', 'status': status, 'purpose': 'sale', 'type': 'shop',
  'price': 100, 'currency': 'YER', 'latitude': 15.3, 'longitude': 44.2,
});
class _Account extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int? id) { state = AsyncData(id == null ? null : _user(id)); }
  void pending() { state = const AsyncLoading(); }
}

void main() {
  test('account and guest histories remain isolated across logout and return', () async {
    final directory = await Directory.systemTemp.createTemp('aqer-recent-test-');
    addTearDown(() => directory.delete(recursive: true));
    final account = _Account();
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => account),
      recentHistoryDirectoryProvider.overrideWithValue(() async => directory)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(recentPropertiesStoreProvider).record(_property(11));
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [11]);
    account.change(2);
    expect(await container.read(recentPropertiesProvider.future), isEmpty);
    await container.read(recentPropertiesStoreProvider).record(_property(22));
    account.change(null);
    expect(await container.read(recentPropertiesProvider.future), isEmpty);
    await container.read(recentPropertiesStoreProvider).record(_property(33));
    account.change(1);
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [11]);
    await container.read(recentPropertiesStoreProvider).clear();
    account.change(2);
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [22]);
    account.change(null);
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [33]);
  });

  test('concurrent visits are ordered, bounded and deduplicated; clear cannot be undone by a queued write', () async {
    final directory = await Directory.systemTemp.createTemp('aqer-recent-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = RecentPropertiesStore(actorId: 1, supportDirectory: () async => directory);
    await Future.wait([for (var id = 1; id <= 35; id++) store.record(_property(id))]);
    var rows = await store.load();
    expect(rows.length, 30); expect(rows.first.id, 35); expect(rows.last.id, 6);
    await store.record(_property(10));
    rows = await store.load(); expect(rows.first.id, 10); expect(rows.map((p) => p.id).toSet().length, 30);
    await store.record(_property(99, status: 'draft'));
    expect((await store.load()).any((p) => p.id == 99), isFalse);
    final write = store.record(_property(100));
    final clear = store.clear();
    await Future.wait([write, clear]);
    expect(await store.load(), isEmpty);
  });

  test('unowned legacy history is not imported and unresolved auth never reads guest history', () async {
    final directory = await Directory.systemTemp.createTemp('aqer-recent-test-');
    addTearDown(() => directory.delete(recursive: true));
    final legacy = File('${directory.path}/aqer_recent_properties.json');
    await legacy.writeAsString('[{"id":999,"status":"published","title":"legacy"}]');
    final guest = RecentPropertiesStore(supportDirectory: () async => directory);
    expect(await guest.load(), isEmpty); expect(await legacy.exists(), isTrue);
    await guest.record(_property(33));
    final account = _Account();
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => account),
      recentHistoryDirectoryProvider.overrideWithValue(() async => directory)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    account.pending();
    expect(await container.read(recentPropertiesProvider.future), isEmpty);
    expect(container.read(recentPropertiesStoreProvider).enabled, isFalse);
    account.change(null);
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [33]);
    await File('${directory.path}/aqer_recent_properties_guest.json').writeAsString('malformed');
    expect(await guest.load(), isEmpty);
  });

  test('temporary directory failure is retryable and does not replace previous history', () async {
    final directory = await Directory.systemTemp.createTemp('aqer-recent-test-');
    addTearDown(() => directory.delete(recursive: true));
    await RecentPropertiesStore(actorId: 1, supportDirectory: () async => directory).record(_property(52));
    var fail = true;
    final store = RecentPropertiesStore(actorId: 1, supportDirectory: () async {
      if (fail) { fail = false; throw const FileSystemException('Synthetic temporary IO failure'); }
      return directory;
    });
    await expectLater(store.load(), throwsA(isA<FileSystemException>()));
    await store.record(_property(11));
    expect((await store.load()).map((p) => p.id), [11, 52]);
  });

  test('a delayed old-account write cannot enter the next account history', () async {
    final directory = await Directory.systemTemp.createTemp('aqer-recent-test-');
    addTearDown(() => directory.delete(recursive: true));
    final gate = Completer<Directory>();
    final account = _Account();
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => account),
      recentHistoryDirectoryProvider.overrideWithValue(() => gate.future)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final old = container.read(recentPropertiesStoreProvider).record(_property(11));
    account.change(2);
    final current = container.read(recentPropertiesProvider.future);
    gate.complete(directory); await old;
    expect(await current, isEmpty);
    expect(await container.read(recentPropertiesStoreProvider).load(), isEmpty);
    account.change(1);
    expect((await container.read(recentPropertiesProvider.future)).map((p) => p.id), [11]);
  });
}
