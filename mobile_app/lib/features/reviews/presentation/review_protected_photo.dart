import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/viewport_media.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/presentation/listing_draft_photo.dart';
import '../data/listing_review_repository.dart';

// Staff evidence remains separate from public media. No disk cache; both
// account/permission changes clear it; leaving the viewport cancels unfinished transfers.
final _reviewPhotoCacheProvider = Provider<ListingPhotoCache>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.asData?.value?.id,
    s.asData?.value?.isActive, s.asData?.value?.permissions.toString())));
  final cache = ListingPhotoCache(maxEntries: 6, maxBytes: 12 * 1024 * 1024, maxImageBytes: 12 * 1024 * 1024);
  ref.onDispose(cache.clear);
  return cache;
});

class ReviewProtectedPhoto extends StatelessWidget {
  const ReviewProtectedPhoto({required this.url, super.key});
  final String url;
  @override
  Widget build(BuildContext context) => ViewportMedia(builder: (_) => _VisibleEvidence(url: url));
}

class _VisibleEvidence extends ConsumerStatefulWidget {
  const _VisibleEvidence({required this.url});
  final String url;
  @override
  ConsumerState<_VisibleEvidence> createState() => _VisibleEvidenceState();
}
class _VisibleEvidenceState extends ConsumerState<_VisibleEvidence> {
  ListingPhotoCache? _cache;
  ListingPhotoLease? _lease;
  Future<Uint8List>? _future;
  String? _url;
  int _retry = 0;
  void _reload() { setState(() { _lease?.release(); _lease = null; _cache = null; _retry++; }); }
  @override
  void dispose() { _lease?.release(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authControllerProvider).asData?.value;
    if (actor == null) {
      _lease?.release(); _lease = null; _cache = null; _future = null;
      return const Center(child: Text('سجّل الدخول لعرض الصورة.'));
    }
    final cache = ref.watch(_reviewPhotoCacheProvider);
    if (_lease == null || !identical(_cache, cache) || _url != widget.url) {
      _lease?.release(); _cache = cache; _url = widget.url;
      _lease = cache.acquire('${widget.url}:$_retry', (cancel) => ref.read(listingReviewRepositoryProvider).protectedImage(widget.url, cancelToken: cancel));
      _future = _lease!.future;
    }
    return FutureBuilder<Uint8List>(future: _future, builder: (_, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      Widget retry() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذر تحميل الصورة.'),
        TextButton(onPressed: _reload, child: const Text('إعادة تحميل الصورة')),
      ]));
      if (snapshot.hasError || snapshot.data == null) return retry();
      return ClipRRect(borderRadius: BorderRadius.circular(AppRadii.control), child: Image.memory(snapshot.data!,
        fit: BoxFit.contain, cacheWidth: 1200, errorBuilder: (_, __, ___) => retry()));
    });
  }
}
