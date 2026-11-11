import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/adaptive_image_policy.dart';
import '../network/conditional_image_prefetch.dart';

final mediaNetworkMonitorProvider = Provider<MediaNetworkMonitor>((ref) => MediaNetworkMonitor());

class MediaNetworkMonitor {
  static const channel = MethodChannel('real_estate/network');
  final policy = AdaptiveImagePolicy();
  Future<ImageNetworkConditions>? _pending;
  DateTime? _checked;
  void reportPrefetch(int requests, int bytes, int hits,
    {ImageNetworkConditions? network, bool? eligible, int? scope}) {
    if (!ConditionalImagePrefetch.enabled) return;
    unawaited(channel.invokeMethod<void>('imagePrefetchMetrics', {
      'enabled': true, 'requests': requests, 'bytes': bytes, 'readyHits': hits,
      'scope': scope ?? 0,
      if (network != null) 'metered': network.metered == null ? -1 : network.metered! ? 1 : 0,
      if (network != null) 'dataSaver': network.dataSaver,
      if (eligible != null) 'eligible': eligible,
    }).catchError((Object _) {}));
  }
  Future<ImageNetworkConditions> snapshot({bool refresh = false}) {
    if (!refresh && _pending != null && _checked != null &&
        DateTime.now().difference(_checked!) < const Duration(seconds: 2)) { return _pending!; }
    _checked = DateTime.now();
    return _pending = _read();
  }
  Future<ImageNetworkConditions> _read() async {
    try {
      final state = await channel.invokeMapMethod<String, dynamic>('imageNetworkState')
        .timeout(const Duration(seconds: 2));
      return ImageNetworkConditions(metered: state?['metered'] as bool?,
        dataSaver: state?['dataSaver'] == true,
        networkKey: state?['networkKey']?.toString() ?? 'unknown',
        transport: state?['transport']?.toString() ?? 'unknown');
    } catch (_) { return const ImageNetworkConditions(); }
  }
}
