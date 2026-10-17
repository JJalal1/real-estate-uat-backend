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
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (_, snapshot) => snapshot.hasData
    ? Image.memory(snapshot.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
    : const Center(child: Icon(Icons.photo_outlined)));
}
