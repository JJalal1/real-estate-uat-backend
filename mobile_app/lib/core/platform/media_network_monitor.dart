import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/adaptive_image_policy.dart';

final mediaNetworkMonitorProvider = Provider<MediaNetworkMonitor>((ref) => MediaNetworkMonitor());

class MediaNetworkMonitor {
  static const channel = MethodChannel('real_estate/network');
  final policy = AdaptiveImagePolicy();
  Future<ImageNetworkConditions>? _pending;
  DateTime? _checked;
  Future<ImageNetworkConditions> snapshot() {
    if (_pending != null && _checked != null &&
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
