import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/listing_account_draft_repository.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_controller.dart';
import 'dart:async';
import 'package:dio/dio.dart';

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
  CancelToken? _cancel;
  Future<Uint8List> _beginLoad() {
    final future=_load();
    // A failure may arrive before the next frame attaches FutureBuilder.
    future.ignore();
    return future;
  }
  Future<Uint8List> _load() async {
    _cancel?.cancel('Image changed');
    if (widget.authenticated) return ref.read(listingAccountDraftRepositoryProvider).photo(widget.url);
    final cancel=CancelToken();_cancel=cancel;
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
  void dispose() { _cancel?.cancel('Image closed');super.dispose(); }
  Widget _retry() => Center(child: TextButton(onPressed: () => setState(() {
    _bytes=_beginLoad();
  }), child: const Text('إعادة تحميل الصورة',textAlign:TextAlign.center)));
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (_, snapshot) {
    if (snapshot.hasError) return _retry();
    if (snapshot.connectionState==ConnectionState.done && snapshot.hasData) return Image.memory(snapshot.data!, fit: widget.fit, cacheWidth:widget.cacheWidth, errorBuilder: (_, __, ___) => _retry());
    return Center(child: Semantics(label:'جارٍ تحميل الصورة',child:const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2))));
  });
}
