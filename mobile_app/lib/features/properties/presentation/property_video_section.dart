import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/property_details.dart';

/// The poster is shown first. No video controller or network media request
/// is constructed until the user explicitly chooses to play.
class PropertyVideoSection extends StatefulWidget {
  const PropertyVideoSection({required this.video, super.key});
  final PropertyVideoItem video;

  @override
  State<PropertyVideoSection> createState() => _PropertyVideoSectionState();
}

class _PropertyVideoSectionState extends State<PropertyVideoSection> {
  bool _playRequested = false;

  @override
  void didUpdateWidget(covariant PropertyVideoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.video.streamUrl != widget.video.streamUrl) {
      _playRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(widget.video.streamUrl);
    final poster = Uri.tryParse(widget.video.posterUrl);
    final allowed = url?.scheme == 'https' && poster?.scheme == 'https';
    if (!allowed) return const SizedBox.shrink();

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
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        widget.video.posterUrl,
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
