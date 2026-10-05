import 'property_marker.dart';

enum FavoriteAvailability { available, unavailable }

/// Account persistence is separate from the currently public property summary.
/// An unavailable item has no PropertyMarker and carries no listing fields.
class FavoriteListItem {
  const FavoriteListItem._({
    required this.propertyId,
    required this.availability,
    this.favoritedAt,
    this.property,
  });

  final int propertyId;
  final FavoriteAvailability availability;
  final DateTime? favoritedAt;
  final PropertyMarker? property;

  bool get isAvailable => availability == FavoriteAvailability.available;

  factory FavoriteListItem.fromJson(Map<String, dynamic> json) {
    final rawProperty = json['property'];
    final summary = rawProperty is Map<String, dynamic> ? rawProperty : null;
    // Keep available cards compatible with the older published-only API.
    final rawId = json['property_id'] ??
        (json['availability'] == null ? summary?['id'] : null);
    final id = int.tryParse(rawId?.toString() ?? '');
    if (id == null || id <= 0) {
      throw const FormatException('Invalid favorite identity');
    }

    final declaredAvailability = json['availability'];
    final available = (declaredAvailability == 'available' ||
            declaredAvailability == null) &&
        summary != null &&
        summary['status'] == 'published' &&
        summary['id'].toString() == id.toString();

    return FavoriteListItem._(
      propertyId: id,
      availability: available
          ? FavoriteAvailability.available
          : FavoriteAvailability.unavailable,
      favoritedAt: DateTime.tryParse(json['favorited_at']?.toString() ?? ''),
      // Explicit unavailable/unknown states ignore even a supplied summary.
      property: available && summary != null
          ? PropertyMarker.fromJson(summary)
          : null,
    );
  }
}
