const String appDeepLinkScheme = 'realestate';
const String appDeepLinkHost = 'app';

Uri propertyAppDeepLink(int propertyId) {
  if (propertyId <= 0) {
    throw ArgumentError.value(propertyId, 'propertyId', 'must be positive');
  }

  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/properties/$propertyId',
  );
}

/// Converts only links owned by this app into an internal GoRouter location.
/// Unknown hosts/schemes are intentionally ignored instead of being rewritten.
String? internalLocationForAppLink(Uri uri) {
  if (uri.scheme != appDeepLinkScheme || uri.host != appDeepLinkHost) {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.length == 2 &&
      segments.first == 'properties' &&
      (int.tryParse(segments.last) ?? 0) > 0) {
    return '/properties/${segments.last}';
  }

  return null;
}
