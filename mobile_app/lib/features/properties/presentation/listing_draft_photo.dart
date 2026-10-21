import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/listing_account_draft_repository.dart';

class ListingDraftPhoto extends ConsumerStatefulWidget {
  const ListingDraftPhoto({required this.url, super.key});
  final String url;
  @override
  ConsumerState<ListingDraftPhoto> createState() => _ListingDraftPhotoState();
}
class _ListingDraftPhotoState extends ConsumerState<ListingDraftPhoto> {
  late Future<Uint8List> _bytes;
  @override
  void initState() { super.initState(); _bytes = ref.read(listingAccountDraftRepositoryProvider).photo(widget.url); }
  @override
  void didUpdateWidget(ListingDraftPhoto oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.url != widget.url) _bytes = ref.read(listingAccountDraftRepositoryProvider).photo(widget.url); }
  @override
  Widget _retry() => Center(child: TextButton(onPressed: () => setState(() {
    _bytes=ref.read(listingAccountDraftRepositoryProvider).photo(widget.url);
  }), child: const Text('إعادة تحميل الصورة',textAlign:TextAlign.center)));
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (_, snapshot) {
    if (snapshot.hasError) return _retry();
    if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover, cacheWidth:500, errorBuilder: (_, __, ___) => _retry());
    return Center(child: Semantics(label:'جارٍ تحميل الصورة',child:const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2))));
  });
}
