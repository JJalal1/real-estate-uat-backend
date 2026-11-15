import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/listing_account_draft_repository.dart';
import '../data/public_photo_disk_cache.dart';
import '../data/public_photo_loader.dart';
import '../data/property_repository.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_controller.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../../../core/network/adaptive_image_policy.dart';
import '../../../core/network/conditional_image_prefetch.dart';
import '../../../core/platform/media_network_monitor.dart';
import '../../../core/widgets/viewport_media.dart';

final listingPhotoCacheProvider = Provider<ListingPhotoCache>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.asData?.value?.id, s.asData?.value?.isActive, s.asData?.value?.permissions.toString())));
  final cache = ListingPhotoCache();
  ref.listen(propertyDataRevisionProvider, (_, __) => cache.clear());
  ref.onDispose(cache.clear);
  return cache;
});

final photoPrefetchBudgetProvider = Provider<PhotoPrefetchBudget>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.asData?.value?.id,
    s.asData?.value?.isActive, s.asData?.value?.permissions.toString())));
  final budget = PhotoPrefetchBudget();ref.onDispose(budget.dispose);return budget;
});

/// No disk storage; successes only, deduplicated requests and bounded account-session memory.
class ListingPhotoCache {
  static int _nextScope = 0;
  final int scope = ++_nextScope;
  ListingPhotoCache({this.maxEntries = 18, this.maxBytes = 24 * 1024 * 1024,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.ttl = const Duration(minutes: 2), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final int maxEntries, maxBytes, maxImageBytes;
  final Duration ttl;
  final DateTime Function() _clock;
  final _entries = <String, _PhotoEntry>{};
  int _epoch = 0;
  int memoryHits = 0, deduplicatedLoads = 0, networkRequests = 0, networkBytes = 0, notModified = 0;
  int prefetchRequests = 0, prefetchBytes = 0, prefetchReadyHits = 0;
  bool hasForegroundLease(String key) => (_entries[key]?.foregroundReferences ?? 0) > 0;
  Uint8List? peek(String key) => _entries[key]?.data;
  Uint8List? peekPublicPreview(String url) {
    if (!AdaptiveImagePolicy.supportsVariants(url)) return null;
    for (final variant in const ['card','thumb','preview','detail']) {
      final bytes = peek('public:${AdaptiveImagePolicy.variantUrl(url, variant)}');
      if (bytes != null) return bytes;
    }
    return null;
  }
  void clear() {
    _epoch++;
    for (final entry in _entries.values) {
      entry.cancellation?.cancel('Account image cache cleared');
      if (entry.data != null) MemoryImage(entry.data!).evict();
    }
    _entries.clear();
  }
  ListingPhotoLease acquire(String key, Future<Uint8List> Function(CancelToken) loader, {bool prefetch = false}) {
    if (_entries[key]?.cancellation?.isCancelled == true && _entries[key]?.completedAt == null) _entries.remove(key);
    final fresh = !_entries.containsKey(key);
    final cancellation = CancelToken();
    final future = load(key, () => loader(cancellation), cancellation: cancellation, retain: true);
    final entry = _entries[key]!;
    if (prefetch && fresh) entry.prefetched = true;
    if (!prefetch) {
      entry.foregroundReferences++;
      if (entry.prefetched && entry.data != null) prefetchReadyHits++;
    }
    return ListingPhotoLease(future, () {
      entry.references--;
      if (!prefetch) entry.foregroundReferences--;
      if (entry.references == 0 && entry.completedAt == null) {
        entry.cancellation?.cancel('Image left viewport');
        if (identical(_entries[key], entry)) _entries.remove(key);
      }
      _trim();
    });
  }
  Future<Uint8List> load(String key, Future<Uint8List> Function() loader, {CancelToken? cancellation, bool retain = false}) {
    _entries.removeWhere((_, e) {
      final expired = e.references == 0 && e.completedAt != null && _clock().difference(e.completedAt!) > ttl;
      if (expired && e.data != null) MemoryImage(e.data!).evict();
      return expired;
    });
    final previous = _entries.remove(key);
    if (previous != null) {
      if (previous.data != null) { memoryHits++; } else { deduplicatedLoads++; }
      if (retain) previous.references++; _entries[key] = previous; return previous.future;
    }
    final epoch = _epoch, entry = _PhotoEntry()..cancellation = cancellation..references = retain ? 1 : 0;
    entry.future = Future<Uint8List>.sync(loader).then((bytes) {
      if (bytes.isEmpty || bytes.lengthInBytes > maxImageBytes) throw StateError('Invalid display image size');
      if (_epoch == epoch && identical(_entries[key], entry)) {
        entry.bytes = bytes.lengthInBytes; entry.data = bytes; entry.completedAt = _clock(); _trim();
      }
      return bytes;
    }).catchError((Object error) {
      if (identical(_entries[key], entry)) _entries.remove(key);
      throw error;
    });
    // A widget may leave before its FutureBuilder attaches.
    entry.future.ignore();
    _entries[key] = entry; _trim(); return entry.future;
  }
  void forget(String key) {
    final entry = _entries.remove(key);
    entry?.cancellation?.cancel('Image retry');
    if (entry?.data != null) MemoryImage(entry!.data!).evict();
  }
  void _trim() {
    while (_entries.length > maxEntries || _entries.values.fold<int>(0, (sum, e) => sum + e.bytes) > maxBytes) {
      final idle = _entries.entries.where((e) => e.value.references == 0);
      if (idle.isEmpty) break;
      final entry = idle.first;
      entry.value.cancellation?.cancel('Image cache evicted');
      if (entry.value.data != null) MemoryImage(entry.value.data!).evict();
      _entries.remove(entry.key);
    }
  }
}
class ListingPhotoLease {
  ListingPhotoLease(this.future, this._release);
  final Future<Uint8List> future;
  final void Function() _release;
  bool _closed = false;
  void close() { if (!_closed) { _closed = true; _release(); } }
}
class _PhotoEntry {
  late Future<Uint8List> future;
  int bytes = 0;
  DateTime? completedAt;
  Uint8List? data;
  CancelToken? cancellation;
  int references = 0;
  int foregroundReferences = 0;
  bool prefetched = false;
}

class ListingDraftPhoto extends ConsumerStatefulWidget {
  const ListingDraftPhoto({required this.url, this.authenticated = true, this.fit = BoxFit.cover,
    this.cacheWidth = 500, this.network, this.onRetry, this.allowPrefetch = false, super.key});
  final String url;
  final bool authenticated;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageNetworkConditions? network;
  final VoidCallback? onRetry;
  final bool allowPrefetch;
  @override
  ConsumerState<ListingDraftPhoto> createState() => _ListingDraftPhotoSlotState();
}

class _ListingDraftPhotoSlotState extends ConsumerState<ListingDraftPhoto> {
  final _owner = Object();
  Timer? _dwell, _poll;
  ListingPhotoLease? _prefetch;
  PhotoPrefetchBudget? _budget;
  bool _nearby = false, _checking = false;
  int _generation = 0;
  String? _failedNetwork;

  bool get _enabled => ref.read(conditionalPrefetchEnabledProvider) &&
    widget.allowPrefetch && !widget.authenticated && widget.network != null &&
    ConditionalImagePrefetch.eligibleUrl(widget.url, Uri.parse(ref.read(dioProvider).options.baseUrl));

  void _release() {
    _generation++;
    _prefetch?.close();_prefetch = null;
    _budget?.release(_owner);_budget = null;
  }
  void _stop() {
    _generation++;_nearby = false;_dwell?.cancel();_dwell = null;
    _poll?.cancel();_poll = null;_release();
  }
  void _viewport(bool nearby, bool visible, bool scrolling) {
    if (visible && _prefetch != null && !scrolling && _enabled) {
      _generation++;_nearby = false;_dwell?.cancel();_dwell = null;_poll?.cancel();_poll = null;
      // The visible child acquires its foreground lease in the next build.
      // Release speculative ownership afterwards so an in-flight transfer is shared.
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !_nearby) _release(); });
      WidgetsBinding.instance.scheduleFrame();return;
    }
    if (!nearby || scrolling || !_enabled) { if (_nearby || _prefetch != null) _stop();return; }
    _nearby = true;
    _poll ??= Timer.periodic(ConditionalImagePrefetch.recheck, (_) => unawaited(_check()));
    _dwell ??= Timer(ConditionalImagePrefetch.dwell, () { unawaited(_check()); });
  }
  Future<void> _check() async {
    if (_checking || !_nearby || !mounted || !_enabled) return;
    _checking = true;final generation = _generation;
    try {
      final monitor = ref.read(mediaNetworkMonitorProvider);
      final network = await monitor.snapshot(refresh: true);
      if (!mounted || generation != _generation || !_nearby || !_enabled) return;
      final cache = ref.read(listingPhotoCacheProvider);
      if (!monitor.policy.canPrefetch(network)) {
        _release();monitor.reportPrefetch(cache.prefetchRequests, cache.prefetchBytes, cache.prefetchReadyHits,
          network: network, eligible: false, scope: cache.scope);return;
      }
      if (_prefetch != null || _failedNetwork == network.networkKey) return;
      final key = 'public:${widget.url}';
      if (cache.peek(key) != null) return;
      final budget = ref.read(photoPrefetchBudgetProvider);
      if (!budget.reserve(_owner)) return;
      _budget = budget;
      _prefetch = cache.acquire(key, (cancel) async {
        cache.prefetchRequests++;cache.networkRequests++;
        var received = 0;
        void counted(int count) {
          if (count > received) { cache.prefetchBytes += count - received;cache.networkBytes += count - received;received = count; }
        }
        try {
          final transfer = await PublicPhotoLoader(ref.read(dioProvider), ref.read(publicPhotoDiskCacheProvider)).load(widget.url,
            cancelToken: cancel, backgroundByteLimit: ConditionalImagePrefetch.maxImageBytes,
            foregroundAttached: () => cache.hasForegroundLease(key), onReceivedBytes: counted, requirePublicResponse: true);
          counted(transfer.downloadedBytes);
          if (transfer.notModified) cache.notModified++;
          return transfer.bytes;
        } finally {
          monitor.reportPrefetch(cache.prefetchRequests, cache.prefetchBytes, cache.prefetchReadyHits,
            network: network, eligible: true, scope: cache.scope);
        }
      }, prefetch: true);
      unawaited(_prefetch!.future.then<void>((_) {}, onError: (Object _) {
        if (mounted && generation == _generation) { _failedNetwork = network.networkKey;_release(); }
      }));
    } finally { _checking = false; }
  }
  @override
  void didUpdateWidget(ListingDraftPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.authenticated != widget.authenticated ||
        oldWidget.allowPrefetch != widget.allowPrefetch) { _stop();_failedNetwork = null; }
  }
  @override
  void dispose() { _stop();super.dispose(); }
  @override
  Widget build(BuildContext context) {
    ref.watch(conditionalPrefetchEnabledProvider);
    if (_enabled) {
      ref.watch(listingPhotoCacheProvider);
      ref.listen(authControllerProvider.select((s) => (s.asData?.value?.id,
        s.asData?.value?.isActive, s.asData?.value?.permissions.toString())), (_, __) => _stop());
    }
    return ViewportMedia(onPrefetchChanged: _enabled ? _viewport : null,
      builder: (_) => _VisibleListingDraftPhoto(url: widget.url, authenticated: widget.authenticated,
        fit: widget.fit, cacheWidth: widget.cacheWidth, network: widget.network, onRetry: widget.onRetry));
  }
}

class _VisibleListingDraftPhoto extends ConsumerStatefulWidget {
  const _VisibleListingDraftPhoto({required this.url, required this.authenticated, required this.fit,
    required this.cacheWidth, required this.network, required this.onRetry});
  final String url;
  final bool authenticated;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageNetworkConditions? network;
  final VoidCallback? onRetry;
  @override
  ConsumerState<_VisibleListingDraftPhoto> createState() => _ListingDraftPhotoState();
}

class _ListingDraftPhotoState extends ConsumerState<_VisibleListingDraftPhoto> {
  late Future<Uint8List> _bytes;
  ListingPhotoLease? _lease;
  Uint8List? _displayBytes;
  Future<Uint8List> _beginLoad() {
    final future=_load();
    // A failure may arrive before the next frame attaches FutureBuilder.
    future.ignore();
    return future;
  }
  String get _cacheKey => '${widget.authenticated ? 'private' : 'public'}:${widget.url}';
  Future<Uint8List> _load() {
    _lease?.close();
    final cache = ref.read(listingPhotoCacheProvider);
    _displayBytes ??= cache.peek(_cacheKey) ?? (widget.authenticated ? null : cache.peekPublicPreview(widget.url));
    _lease = cache.acquire(_cacheKey, _fetch);
    if (!widget.authenticated) {
      ref.read(mediaNetworkMonitorProvider).reportPrefetch(
        cache.prefetchRequests, cache.prefetchBytes, cache.prefetchReadyHits, scope: cache.scope);
    }
    return _lease!.future;
  }
  Future<Uint8List> _fetch(CancelToken cancel) async {
    final timer = Stopwatch()..start();
    final network = widget.network;
    final monitor = ref.read(mediaNetworkMonitorProvider);
    final statistics = ref.read(listingPhotoCacheProvider);
    var transferredBytes = 0;
    Uint8List bytes;
    if (widget.authenticated) {
      statistics.networkRequests++;
      try {
        bytes = await ref.read(listingAccountDraftRepositoryProvider).photo(widget.url, cancelToken: cancel);
      } on DioException catch (error) {
        if (const [401,403,404].contains(error.response?.statusCode) && mounted) setState(() => _displayBytes = null);
        rethrow;
      }
      transferredBytes = bytes.lengthInBytes;
    } else {
    statistics.networkRequests++;
    try {
      final result = await PublicPhotoLoader(ref.read(dioProvider), ref.read(publicPhotoDiskCacheProvider))
        .load(widget.url, cancelToken: cancel);
      bytes = result.bytes;
      transferredBytes = result.downloadedBytes;
      if (result.notModified) statistics.notModified++;
    } on DioException catch (error) {
      if (const [401,403,404].contains(error.response?.statusCode) && mounted) setState(() => _displayBytes = null);
      rethrow;
    }
    }
    statistics.networkBytes += transferredBytes;
    if (network != null) monitor.policy.recordTransfer(network, transferredBytes, timer.elapsed);
    return bytes;
  }
  @override
  void initState() {
    super.initState(); _bytes = _beginLoad();
    ref.listenManual(authControllerProvider.select((state)=>(state.asData?.value?.id,
      state.asData?.value?.isActive, state.asData?.value?.permissions.toString())),(_,next) {
      if (widget.authenticated && mounted) setState(() { _displayBytes = null; _bytes=_beginLoad(); });
    });
  }
  @override
  void didUpdateWidget(_VisibleListingDraftPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.authenticated != widget.authenticated) {
      String identity(String url) {
        final uri = Uri.parse(url), parameters = Map<String, String>.from(Uri.parse(url).queryParameters)..remove('variant');
        return uri.replace(queryParameters: parameters).toString();
      }
      if (identity(oldWidget.url) != identity(widget.url) ||
          oldWidget.authenticated != widget.authenticated) { _displayBytes = null; }
      _bytes = _beginLoad();
    }
  }
  @override
  void dispose() { _lease?.close(); super.dispose(); }
  Widget _retry() => Center(child: TextButton(onPressed: () {
    if (widget.onRetry != null) { widget.onRetry!(); return; }
    setState(() {
    ref.read(listingPhotoCacheProvider).forget(_cacheKey);
    if (!widget.authenticated) unawaited(ref.read(publicPhotoDiskCacheProvider).forget(widget.url));
    _bytes=_beginLoad();
    });
  }, child: const Text('إعادة تحميل الصورة',textAlign:TextAlign.center)));
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (_, snapshot) {
    if (snapshot.connectionState==ConnectionState.done && snapshot.hasData) { _displayBytes = snapshot.data; }
    if (_displayBytes != null) { return Stack(fit: StackFit.expand, children: [
      Image.memory(_displayBytes!, fit: widget.fit, cacheWidth:widget.cacheWidth, gaplessPlayback:true,
        errorBuilder: (_, __, ___) => _retry()),
      if (snapshot.hasError) Align(alignment:Alignment.bottomCenter, child: _retry()),
    ]); }
    if (snapshot.hasError) return _retry();
    return Center(child: Semantics(label:'جارٍ تحميل الصورة',child:const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2))));
  });
}
