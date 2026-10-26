import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/property_details.dart';
import '../../../core/network/api_client.dart';

/// The poster is shown first. No video controller or network media request
/// is constructed until the user explicitly chooses to play.
class PropertyVideoSection extends StatefulWidget {
  const PropertyVideoSection({required this.video, this.requestHeaders = const <String, String>{}, super.key});
  final PropertyVideoItem video;
  final Map<String, String> requestHeaders;

  @override
  State<PropertyVideoSection> createState() => _PropertyVideoSectionState();
}

class _PropertyVideoSectionState extends State<PropertyVideoSection> with WidgetsBindingObserver {
  bool _playRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playRequested) {
      setState(() => _playRequested = false);
    }
  }

  @override
  void didUpdateWidget(covariant PropertyVideoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id || oldWidget.video.streamUrl != widget.video.streamUrl ||
        !mapEquals(oldWidget.requestHeaders, widget.requestHeaders)) {
      _playRequested = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(widget.video.streamUrl);
    final poster = Uri.tryParse(widget.video.posterUrl);
    final allowed = url?.scheme == 'https' && poster?.scheme == 'https';
    if (!allowed) return const SizedBox.shrink();
    if (widget.requestHeaders.isNotEmpty) {
      final api = Uri.tryParse(ApiEnvironmentConfig.resolveBaseUrl());
      final prefix = api == null ? '' : (api.path.endsWith('/') ? api.path.substring(0, api.path.length - 1) : api.path);
      if (api?.scheme != 'https' ||
          url?.origin != api?.origin ||
          poster?.origin != api?.origin ||
          url?.path != '$prefix/property-videos/${widget.video.id}/stream' ||
          poster?.path != '$prefix/property-videos/${widget.video.id}/poster' ||
          url?.hasQuery == true || poster?.hasQuery == true ||
          url?.hasFragment == true || poster?.hasFragment == true ||
          url?.userInfo.isNotEmpty == true || poster?.userInfo.isNotEmpty == true) {
        return const SizedBox.shrink();
      }
    }

    final supported = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Text('فيديو العقار', style: Theme.of(context).textTheme.titleMedium),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _playRequested && supported
                ? AndroidView(
                    key: ValueKey('property-video-${widget.video.id}'),
                    viewType: 'aqer/listing-video',
                    creationParams: <String, Object>{
                      'url': widget.video.streamUrl,
                      if (widget.requestHeaders.isNotEmpty) 'headers': widget.requestHeaders,
                      if (widget.requestHeaders.isNotEmpty) 'apiOrigin': Uri.parse(ApiEnvironmentConfig.resolveBaseUrl()).origin,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        widget.video.posterUrl,
                        headers: widget.requestHeaders.isEmpty ? null : widget.requestHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.videocam_off_outlined)),
                        ),
                      ),
                      Center(
                        child: FilledButton.icon(
                          onPressed: supported
                              ? () => setState(() => _playRequested = true)
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(supported ? 'تشغيل الفيديو' : 'التشغيل غير متاح على هذا الجهاز'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
