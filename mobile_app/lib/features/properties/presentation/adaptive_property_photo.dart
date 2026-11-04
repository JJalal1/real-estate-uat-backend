import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/adaptive_image_policy.dart';
import '../../../core/platform/media_network_monitor.dart';
import 'listing_draft_photo.dart';

class AdaptivePropertyPhoto extends ConsumerStatefulWidget {
  const AdaptivePropertyPhoto({required this.url, this.authenticated = false,
    this.use = PropertyImageUse.card, this.fit = BoxFit.cover, super.key});
  final String url;
  final bool authenticated;
  final PropertyImageUse use;
  final BoxFit fit;
  @override
  ConsumerState<AdaptivePropertyPhoto> createState() => _AdaptivePropertyPhotoState();
}

class _AdaptivePropertyPhotoState extends ConsumerState<AdaptivePropertyPhoto> with WidgetsBindingObserver {
  late Future<ImageNetworkConditions> _network;
  int _retryGeneration = 0;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _network = ref.read(mediaNetworkMonitorProvider).snapshot();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() { _network = ref.read(mediaNetworkMonitorProvider).snapshot(refresh: true); });
    }
  }
  @override
  void didUpdateWidget(AdaptivePropertyPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.use != widget.use) {
      _network = ref.read(mediaNetworkMonitorProvider).snapshot();
    }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final width = bounds.maxWidth.isFinite ? bounds.maxWidth : MediaQuery.sizeOf(context).width;
    final height = bounds.maxHeight.isFinite ? bounds.maxHeight : width;
    final edge = width > height ? width : height;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<ImageNetworkConditions>(future: _network, builder: (context, snapshot) {
      if (!snapshot.hasData) { return const Center(child: SizedBox(width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2))); }
      final monitor = ref.read(mediaNetworkMonitorProvider);
      final variant = monitor.policy.choose(use: widget.use, logicalEdge: edge,
        pixelRatio: dpr, network: snapshot.data!);
      return ListingDraftPhoto(key:ValueKey(_retryGeneration),url: AdaptiveImagePolicy.variantUrl(widget.url, variant),
        authenticated: widget.authenticated, fit: widget.fit,
        cacheWidth: variant == 'zoom' ? 3072 : (edge * dpr).round().clamp(128, 1920).toInt(),
        network: snapshot.data, onRetry:() => setState(() {
          _retryGeneration++;
          _network = ref.read(mediaNetworkMonitorProvider).snapshot(refresh: true);
        }));
    });
  });
}
