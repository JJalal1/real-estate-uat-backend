import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/listing_account_draft_repository.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_controller.dart';
import 'dart:async';
import 'package:dio/dio.dart';

final listingPhotoCacheProvider = Provider<ListingPhotoCache>((ref) {
  ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  final cache = ListingPhotoCache();
  ref.onDispose(cache.clear);
  return cache;
});

/// No disk storage; successes only, deduplicated requests and bounded account-session memory.
class ListingPhotoCache {
  ListingPhotoCache({this.maxEntries = 18, this.maxBytes = 24 * 1024 * 1024,
    this.ttl = const Duration(minutes: 2), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final int maxEntries, maxBytes;
  final Duration ttl;
  final DateTime Function() _clock;
  final _entries = <String, _PhotoEntry>{};
  int _epoch = 0;
  void clear() { _epoch++; _entries.clear(); }
  Future<Uint8List> load(String key, Future<Uint8List> Function() loader) {
    _entries.removeWhere((_, e) => e.completedAt != null && _clock().difference(e.completedAt!) > ttl);
    final previous = _entries.remove(key);
    if (previous != null) { _entries[key] = previous; return previous.future; }
    final epoch = _epoch, entry = _PhotoEntry();
    entry.future = Future<Uint8List>.sync(loader).then((bytes) {
      if (bytes.isEmpty || bytes.lengthInBytes > 8 * 1024 * 1024) throw StateError('Invalid display image size');
      if (_epoch == epoch && identical(_entries[key], entry)) {
        entry.bytes = bytes.lengthInBytes; entry.completedAt = _clock(); _trim();
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
  void forget(String key) { _entries.remove(key); }
  void _trim() {
    while (_entries.length > maxEntries || _entries.values.fold<int>(0, (sum, e) => sum + e.bytes) > maxBytes) {
      _entries.remove(_entries.keys.first);
    }
  }
}
class _PhotoEntry {
  late Future<Uint8List> future;
  int bytes = 0;
  DateTime? completedAt;
}

class ListingDraftPhoto extends ConsumerStatefulWidget {
  const ListingDraftPhoto({required this.url, this.authenticated = true, this.fit = BoxFit.cover, this.cacheWidth = 500, super.key});
  final String url;
  final bool authenticated;
  final BoxFit fit;
  final int? cacheWidth;
  @override
  ConsumerState<ListingDraftPhoto> createState() => _ListingDraftPhotoState();
}
class _ListingDraftPhotoState extends ConsumerState<ListingDraftPhoto> {
  late Future<Uint8List> _bytes;
  Future<Uint8List> _beginLoad() {
    final future=_load();
    // A failure may arrive before the next frame attaches FutureBuilder.
    future.ignore();
    return future;
  }
  String get _cacheKey => '${widget.authenticated ? "private" : "public"}:${widget.url}';
  Future<Uint8List> _load() => ref.read(listingPhotoCacheProvider).load(_cacheKey, _fetch);
  Future<Uint8List> _fetch() async {
    if (widget.authenticated) return ref.read(listingAccountDraftRepositoryProvider).photo(widget.url);
    final cancel=CancelToken();
    final response=await ref.read(dioProvider).get<List<int>>(widget.url,options:Options(responseType:ResponseType.bytes),cancelToken:cancel)
      .timeout(const Duration(seconds:25),onTimeout:() { cancel.cancel('Image deadline');throw TimeoutException('Image unavailable'); });
    return Uint8List.fromList(response.data ?? const []);
  }
  @override
  void initState() {
    super.initState(); _bytes = _beginLoad();
    ref.listenManual(authControllerProvider.select((state)=>state.asData?.value?.id),(_,next) {
      if (widget.authenticated && mounted) setState(() { _bytes=_beginLoad(); });
    });
  }
  @override
  void didUpdateWidget(ListingDraftPhoto oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.url != widget.url || oldWidget.authenticated != widget.authenticated) _bytes = _beginLoad(); }
  @override
  void dispose() { super.dispose(); }
  Widget _retry() => Center(child: TextButton(onPressed: () => setState(() {
    ref.read(listingPhotoCacheProvider).forget(_cacheKey);
    _bytes=_beginLoad();
  }), child: const Text('إعادة تحميل الصورة',textAlign:TextAlign.center)));
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (_, snapshot) {
    if (snapshot.hasError) return _retry();
    if (snapshot.connectionState==ConnectionState.done && snapshot.hasData) return Image.memory(snapshot.data!, fit: widget.fit, cacheWidth:widget.cacheWidth, errorBuilder: (_, __, ___) => _retry());
    return Center(child: Semantics(label:'جارٍ تحميل الصورة',child:const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2))));
  });
}
