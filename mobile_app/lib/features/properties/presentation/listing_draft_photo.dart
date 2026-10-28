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
import '../../../core/platform/media_network_monitor.dart';
import '../../../core/widgets/viewport_media.dart';

final listingPhotoCacheProvider = Provider<ListingPhotoCache>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.asData?.value?.id, s.asData?.value?.isActive, s.asData?.value?.permissions.toString())));
  final cache = ListingPhotoCache();
  ref.listen(propertyDataRevisionProvider, (_, __) => cache.clear());
  ref.onDispose(cache.clear);
  return cache;
});

/// No disk storage; successes only, deduplicated requests and bounded account-session memory.
class ListingPhotoCache {
  ListingPhotoCache({this.maxEntries = 18, this.maxBytes = 24 * 1024 * 1024,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.ttl = const Duration(minutes: 2), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final int maxEntries, maxBytes, maxImageBytes;
  final Duration ttl;
  final DateTime Function() _clock;
  final _entries = <String, _PhotoEntry>{};
  int _epoch = 0;
  int memoryHits = 0, deduplicatedLoads = 0, networkRequests = 0, networkBytes = 0, notModified = 0;
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
  ListingPhotoLease acquire(String key, Future<Uint8List> Function(CancelToken) loader) {
    final cancellation = CancelToken();
    final future = load(key, () => loader(cancellation), cancellation: cancellation, retain: true);
    final entry = _entries[key]!;
    return ListingPhotoLease(future, () {
      entry.references--;
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
}

class ListingDraftPhoto extends StatelessWidget {
  const ListingDraftPhoto({required this.url, this.authenticated = true, this.fit = BoxFit.cover, this.cacheWidth = 500, this.network, this.onRetry, super.key});
  final String url;
  final bool authenticated;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageNetworkConditions? network;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => ViewportMedia(builder: (_) => _VisibleListingDraftPhoto(
    url: url, authenticated: authenticated, fit: fit, cacheWidth: cacheWidth, network: network, onRetry: onRetry));
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
      if (Uri.parse(oldWidget.url).replace(query: '').toString() != Uri.parse(widget.url).replace(query: '').toString() ||
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

