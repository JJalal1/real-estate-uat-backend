import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A failed account lookup is unknown, never an unsaved property.
class PropertyFavoriteStatus {
  const PropertyFavoriteStatus.ready(this.selected) : loading = false, failed = false;
  const PropertyFavoriteStatus.loading() : selected = false, loading = true, failed = false;
  const PropertyFavoriteStatus.failed() : selected = false, loading = false, failed = true;

  factory PropertyFavoriteStatus.fromAsync(AsyncValue<Set<int>>? ids, int propertyId) {
    if (ids == null) return const PropertyFavoriteStatus.ready(false);
    if (ids.isLoading) return const PropertyFavoriteStatus.loading();
    if (ids.hasError) return const PropertyFavoriteStatus.failed();
    final data = ids.asData;
    return data == null ? const PropertyFavoriteStatus.loading()
        : PropertyFavoriteStatus.ready(data.value.contains(propertyId));
  }

  final bool selected, loading, failed;
  String get tooltip => loading ? 'جارٍ تحميل المفضلة'
      : failed ? 'إعادة تحميل المفضلة'
      : selected ? 'إزالة من المفضلة' : 'حفظ في المفضلة';
  IconData get icon => loading ? Icons.hourglass_top_rounded
      : failed ? Icons.refresh_rounded
      : selected ? Icons.favorite_rounded : Icons.favorite_border_rounded;
}
