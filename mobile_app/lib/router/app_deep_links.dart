const String appDeepLinkScheme = 'realestate';
const String appDeepLinkHost = 'app';
const String _configuredShareBaseUrl = String.fromEnvironment(
  'APP_SHARE_BASE_URL',
  defaultValue: 'https://real-estate-uat-api-frankfurt.onrender.com',
);

Uri propertyPublicShareLink(int propertyId) {
  _requirePositive(propertyId, 'propertyId');
  final base = Uri.parse(_configuredShareBaseUrl);
  return base.replace(path: '/l/properties/$propertyId', query: null, fragment: null);
}

Uri propertyAppDeepLink(int propertyId) {
  _requirePositive(propertyId, 'propertyId');
  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/properties/$propertyId',
  );
}

Uri messageThreadAppDeepLink(int threadId) {
  _requirePositive(threadId, 'threadId');
  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/messages/$threadId',
  );
}

Uri viewingBookingAppDeepLink(int bookingId) {
  _requirePositive(bookingId, 'bookingId');
  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/bookings/$bookingId',
  );
}

Uri agreementAppDeepLink(int agreementId) {
  _requirePositive(agreementId, 'agreementId');
  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/agreements/$agreementId',
  );
}

Uri rentalContractAppDeepLink(int contractId) {
  _requirePositive(contractId, 'contractId');
  return Uri(
    scheme: appDeepLinkScheme,
    host: appDeepLinkHost,
    path: '/rental-contracts/$contractId',
  );
}

/// Converts only links owned by this app into an internal GoRouter location.
/// Unknown hosts/schemes are intentionally ignored instead of being rewritten.
String? internalLocationForAppLink(Uri uri) {
  final shareBase = Uri.tryParse(_configuredShareBaseUrl);
  final isCustomLink = uri.scheme == appDeepLinkScheme && uri.host == appDeepLinkHost;
  final isPublicShareLink = shareBase != null &&
      uri.scheme == shareBase.scheme &&
      uri.host == shareBase.host &&
      uri.pathSegments.length == 3 &&
      uri.pathSegments[0] == 'l' &&
      uri.pathSegments[1] == 'properties';

  if (isPublicShareLink) {
    final id = int.tryParse(uri.pathSegments[2]) ?? 0;
    return id > 0 ? '/properties/$id' : null;
  }
  if (!isCustomLink) return null;

  final segments = uri.pathSegments;
  if (segments.length == 3 && segments[0] == 'broker' && segments[1] == 'deals') {
    final id = int.tryParse(segments[2]) ?? 0;
    return id > 0 ? '/broker/deals/$id' : null;
  }
  if (segments.length == 2) {
    final id = int.tryParse(segments.last) ?? 0;
    if (id <= 0) return null;

    if (segments.first == 'properties') {
      return '/properties/$id';
    }
    if (segments.first == 'advertisers') return '/advertisers/$id';
    if (segments.first == 'messages') {
      return '/messages/$id';
    }
    if (segments.first == 'bookings') {
      return '/messages';
    }
    if (segments.first == 'agreements') {
      return '/agreements/$id';
    }
    if (segments.first == 'rental-contracts') {
      return '/rental-contracts/$id';
    }
  }

  return null;
}

void _requirePositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}
