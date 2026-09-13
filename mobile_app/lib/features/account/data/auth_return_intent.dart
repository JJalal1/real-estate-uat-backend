import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A short-lived in-memory destination used when a public action requires
/// authentication. It deliberately contains only an internal application path
/// and never credentials or user data.
final authReturnLocationProvider = StateProvider<String?>((ref) => null);

void setAuthReturnLocation(WidgetRef ref, String location) {
  if (!location.startsWith('/')) {
    throw ArgumentError.value(location, 'location', 'must be an internal path');
  }
  ref.read(authReturnLocationProvider.notifier).state = location;
}

String takeAuthReturnLocation(WidgetRef ref, {String fallback = '/'}) {
  final location = ref.read(authReturnLocationProvider);
  ref.read(authReturnLocationProvider.notifier).state = null;
  return location ?? fallback;
}
