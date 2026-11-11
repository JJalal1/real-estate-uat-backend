import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final conditionalPrefetchEnabledProvider = Provider<bool>((_) => ConditionalImagePrefetch.enabled);

/// Owner-authorized UAT experiment. Other environments keep visible-only media.
abstract final class ConditionalImagePrefetch {
  static const requested = bool.fromEnvironment('AQER_CONDITIONAL_PREFETCH');
  static bool get enabled => ApiEnvironmentConfig.isUat && requested;
  static const maxImages = 2;
  static const maxImageBytes = 512 * 1024;
  static const extent = 240.0;
  static const dwell = Duration(milliseconds: 250);
  static const recheck = Duration(seconds: 2);

  static bool eligibleUrl(String url, Uri origin) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty || uri.hasFragment ||
        uri.scheme != origin.scheme || uri.host != origin.host || uri.port != origin.port ||
        !RegExp(r'^/api/property-media/[1-9][0-9]*$').hasMatch(uri.path) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters.keys.any((key) => key != 'variant' && key != 'v')) return false;
    final loopback = const ['127.0.0.1', 'localhost', '::1'].contains(uri.host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) return false;
    final version = uri.queryParameters['v'];
    return const ['thumb', 'card'].contains(uri.queryParameters['variant']) &&
        (version == null || RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(version));
  }
}

class PhotoPrefetchBudget {
  final _owners = <Object>{};
  bool _disposed = false;
  bool reserve(Object owner) {
    if (_disposed) return false;
    if (_owners.contains(owner)) return true;
    if (_owners.length >= ConditionalImagePrefetch.maxImages) return false;
    _owners.add(owner);return true;
  }
  void release(Object owner) => _owners.remove(owner);
  void dispose() { _disposed = true;_owners.clear(); }
}
