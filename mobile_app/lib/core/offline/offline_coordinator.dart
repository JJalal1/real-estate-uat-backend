import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maps;
import '../local/stage6_secure_session_store.dart';
import '../network/api_client.dart';
import '../../features/account/data/auth_controller.dart';
import '../../features/discovery/data/marketplace_repository.dart';
import '../../features/discovery/data/marketplace_search_session.dart';
import '../../features/discovery/domain/smart_search_filters.dart';
import '../../features/messages/data/message_outbox.dart';
import 'offline_connection.dart';
import 'offline_store.dart';

class OfflineCoordinator extends ConsumerStatefulWidget {
  const OfflineCoordinator({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<OfflineCoordinator> createState() => _OfflineCoordinatorState();
}

class _OfflineCoordinatorState extends ConsumerState<OfflineCoordinator>
    with WidgetsBindingObserver {
  Timer? _timer, _saveTimer;
  String? _restoredKey;
  bool _restoring = false;
  String get _actorKey =>
      'actor:${ref.read(authControllerProvider).asData?.value?.id ?? 'guest'}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final monitor = ref.read(offlineConnectionProvider.notifier);
    monitor.configure(ref.read(dioProvider).options.baseUrl);
    ref.listenManual(offlineConnectionProvider, (previous, next) {
      unawaited(maps
          .setOffline(next == OfflineConnection.offline)
          .catchError((Object _) => null));
      if (next == OfflineConnection.offline) unawaited(_restoreDiscovery());
      if (next == OfflineConnection.online && previous != next) {
        if (previous == OfflineConnection.offline || monitor.usedSnapshot) {
          ref.read(offlineResumeRevisionProvider.notifier).state++;
          final search = ref.read(marketplaceSearchControllerProvider.notifier);
          if (search.active) unawaited(search.refresh());
        }
        _flush();
        _queueSave();
      }
    });
    ref.listenManual(authControllerProvider, (_, next) {
      if (!next.isLoading) unawaited(_restoreDiscovery());
    });
    ref.listenManual(homeLocationProvider, (_, __) => _queueSave());
    ref.listenManual(
        marketplaceSearchControllerProvider, (_, __) => _queueSave());
    ref.listenManual(homeSearchResultsProvider, (_, __) => _queueSave());
    ref.listenManual(marketplaceMapResultsProvider, (_, __) => _queueSave());
    _start();
  }

  void _start() {
    _timer?.cancel();
    unawaited(ref.read(offlineConnectionProvider.notifier).check(force: true));
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(ref.read(offlineConnectionProvider.notifier).check());
      _flush();
    });
  }

  void _flush() {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor != null &&
        ref.read(offlineConnectionProvider) == OfflineConnection.online) {
      unawaited(ref
          .read(messageOutboxProvider(actor).notifier)
          .flush()
          .catchError((Object _) {}));
    }
  }

  void _queueSave() {
    if (_restoring ||
        ref.read(offlineConnectionProvider) != OfflineConnection.online ||
        ref.read(authControllerProvider).isLoading) { return; }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveDiscovery);
  }

  Future<void> _saveDiscovery() async {
    if (!mounted ||
        _restoring ||
        ref.read(offlineConnectionProvider) != OfflineConnection.online) { return; }
    final ui = ref.read(marketplaceSearchControllerProvider),
        location = ref.read(homeLocationProvider);
    final home = ref.read(homeSearchResultsProvider),
        map = ref.read(marketplaceMapResultsProvider);
    if (home.loading ||
        home.resultsError != null ||
        map.loading ||
        map.resultsError != null) { return; }
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch,
        key = _actorKey;
    try {
      await ref.read(offlineStoreProvider).write(
          'discovery',
          key,
          {
            'location': {
              'latitude': location.latitude,
              'longitude': location.longitude,
              'governorate': location.governorate,
              'governorate_code': location.governorateCode,
              'label': location.label,
              'manual': location.manual,
              'device': location.device,
              'accuracy_m': location.accuracyMetres,
              'needs_confirmation': location.needsConfirmation
            },
            'active': ui.active,
            'criteria': ui.criteria.values,
            'submitted': ui.submittedQuery,
            'draft': ui.draftQuery,
            'land_use': ui.landUse,
            'home_started': home.started,
            'home_filters': home.filters.values,
            'home_pages': home.page,
            'map_started': map.started,
            'map_filters': map.filters.values,
            'map_pages': map.page,
          },
          private: true,
          current: () =>
              mounted &&
              epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
              key == _actorKey);
    } catch (_) {/* Browsing continues if app-private storage is full. */}
  }

  Future<void> _restoreDiscovery() async {
    if (!mounted ||
        _restoring ||
        ref.read(offlineConnectionProvider) != OfflineConnection.offline ||
        ref.read(authControllerProvider).isLoading) { return; }
    final key = _actorKey,
        epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    if (_restoredKey == key) return;
    _restoring = true;
    bool current() =>
        mounted &&
        key == _actorKey &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
        ref.read(offlineConnectionProvider) == OfflineConnection.offline;
    try {
      final saved = await ref
          .read(offlineStoreProvider)
          .read('discovery', key, private: true);
      if (!current()) return;
      final search = ref.read(marketplaceSearchControllerProvider);
      if (search.active ||
          search.draftQuery.isNotEmpty ||
          search.criteria.values.isNotEmpty) { return; }
      _restoredKey = key;
      if (saved != null && saved['location'] is Map) {
        final place = saved['location'] as Map;
        final latitude = (place['latitude'] as num?)?.toDouble(),
            longitude = (place['longitude'] as num?)?.toDouble();
        if (latitude != null &&
            longitude != null &&
            latitude.isFinite &&
            longitude.isFinite &&
            latitude.abs() <= 90 &&
            longitude.abs() <= 180) {
          ref.read(homeLocationProvider.notifier).state = HomeLocation(
              latitude: latitude,
              longitude: longitude,
              governorate: place['governorate']?.toString(),
              governorateCode: place['governorate_code']?.toString(),
              label: place['label']?.toString() ?? 'المنطقة',
              manual: place['manual'] == true,
              device: place['device'] == true,
              accuracyMetres: (place['accuracy_m'] as num?)?.toDouble(),
              needsConfirmation: place['needs_confirmation'] == true);
        }
        await ref
            .read(marketplaceSearchControllerProvider.notifier)
            .restoreOfflineSession(saved, current: current);
        return;
      }
      // A saved feed from before the UI checkpoint is also safe to reopen.
      final record = await ref
          .read(offlineStoreProvider)
          .read('http_snapshots', 'latest_marketplace', private: true);
      if (!current()) return;
      final context =
          ((record?['body'] as Map?)?['data'] as Map?)?['context'] as Map?;
      if (context == null) return;
      final location = ref.read(homeLocationProvider),
          code = context['governorate_code']?.toString(),
          name = context['governorate']?.toString();
      if (location.manual &&
          location.governorateCode != null &&
          code != location.governorateCode) { return; }
      if (!location.manual && name != null)
        { ref.read(homeLocationProvider.notifier).state = HomeLocation(
            governorate: name,
            governorateCode: code,
            label: context['label']?.toString() ?? name); }
      final filters = context['filters'];
      if (filters is Map)
        { ref
            .read(marketplaceSearchControllerProvider.notifier)
            .restoreOfflineHomeCriteria(SmartSearchFilters.fromApiFilters(
                Map<String, dynamic>.from(filters))); }
    } catch (_) {
      /* Keep the visible journey if a snapshot cannot be restored. */
    } finally {
      _restoring = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
      _saveTimer?.cancel();
      unawaited(_saveDiscovery());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(offlineConnectionProvider);
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    if (actor != null) ref.watch(messageOutboxProvider(actor));
    return Column(children: [
      if (connection == OfflineConnection.offline)
        Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SafeArea(
                bottom: false,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.cloud_off_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text(
                              'غير متصل — آخر بيانات محفوظة. الرسائل المعلّقة تنتظر الاتصال.',
                              style: TextStyle(fontSize: 12))),
                      IconButton(
                          tooltip: 'إعادة الاتصال',
                          onPressed: () => ref
                              .read(offlineConnectionProvider.notifier)
                              .check(force: true),
                          icon: const Icon(Icons.refresh, size: 20))
                    ])))),
      Expanded(child: widget.child),
    ]);
  }
}
