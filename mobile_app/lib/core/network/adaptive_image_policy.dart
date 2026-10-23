enum PropertyImageUse { thumbnail, card, detail, fullscreen, zoom }

class ImageNetworkConditions {
  const ImageNetworkConditions({this.metered, this.dataSaver = false,
    this.networkKey = 'unknown', this.transport = 'unknown'});
  final bool? metered;
  final bool dataSaver;
  final String networkKey, transport;
}

/// Uses OS cost policy and actual foreground transfers. Never speed-tests or
/// assumes Wi-Fi is fast/free. Samples expire and cannot cross networks.
class AdaptiveImagePolicy {
  AdaptiveImagePolicy({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  String? _sampleNetwork;
  DateTime? _sampleAt;
  double? _bytesPerSecond;

  void recordTransfer(ImageNetworkConditions network, int bytes, Duration elapsed) {
    if (bytes < 16384 || elapsed.inMilliseconds < 1) return;
    final rate = bytes * 1000 / elapsed.inMilliseconds;
    final fresh = _sampleNetwork == network.networkKey && _sampleAt != null &&
      _clock().difference(_sampleAt!) < const Duration(seconds: 60);
    _bytesPerSecond = fresh ? .5 * _bytesPerSecond! + .5 * rate : rate;
    _sampleNetwork = network.networkKey; _sampleAt = _clock();
  }

  bool isSlow(ImageNetworkConditions network) => _sampleNetwork == network.networkKey &&
    _sampleAt != null && _clock().difference(_sampleAt!) < const Duration(seconds: 60) &&
    (_bytesPerSecond ?? double.infinity) < 128 * 1024;

  String choose({required PropertyImageUse use, required double logicalEdge,
    required double pixelRatio, required ImageNetworkConditions network}) {
    if (use == PropertyImageUse.zoom) return 'zoom'; // explicit user request only
    if (use == PropertyImageUse.thumbnail) return 'thumb';
    final conserve = network.metered != false || network.dataSaver || isSlow(network);
    if (use == PropertyImageUse.card) {
      return conserve || logicalEdge * pixelRatio <= 320 ? 'thumb' : 'card';
    }
    if (conserve) return 'card';
    final pixels = (logicalEdge * pixelRatio).clamp(1, 1920);
    if (pixels <= 640) return 'card';
    if (pixels <= 960) return 'preview';
    if (pixels <= 1280 || use == PropertyImageUse.detail) return 'detail';
    return 'gallery';
  }

  static bool supportsVariants(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.userInfo.isEmpty &&
      (RegExp(r'^/api/property-media/[1-9][0-9]*$').hasMatch(uri.path) ||
       RegExp(r'^/api/listing-editor-drafts/[a-f0-9-]{36}/images/(?:[a-f0-9-]{36}|property-[1-9][0-9]*)$').hasMatch(uri.path));
  }

  static String variantUrl(String url, String variant) {
    if (!supportsVariants(url)) return url; // preserve legacy/CDN contracts
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 'variant': variant}).toString();
  }
}
