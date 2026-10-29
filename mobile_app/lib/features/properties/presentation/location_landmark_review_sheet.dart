import 'package:flutter/material.dart';
import '../../../core/widgets/app_components.dart';
import '../domain/property_location_address.dart';

class LocationLandmarkReviewSheet extends StatefulWidget {
  const LocationLandmarkReviewSheet({required this.landmarks, super.key});
  final List<PropertyNearbyLandmark> landmarks;
  @override
  State<LocationLandmarkReviewSheet> createState() => _LocationLandmarkReviewState();
}
class _LocationLandmarkReviewState extends State<LocationLandmarkReviewSheet> {
  final _text = TextEditingController();
  String? _selected;
  @override
  void dispose() { _text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('راجع وصف الموقع', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(child: ListView(key: const ValueKey('landmark-review-list'), shrinkWrap: true, children: [
            Text(widget.landmarks.isEmpty ? 'لم يرجع المصدر معالم موثوقة قريبة. اكتب معلماً تعرفه إن رغبت، أو تابع دون وصف إضافي.'
              : 'هذه معالم مسجلة على الخريطة وتحتاج مراجعتك. المسافة بخط مستقيم، وليست مسافة طريق أو زمن مشي.'),
            for (final landmark in widget.landmarks) RadioListTile<String>(
              key: ValueKey('landmark-${landmark.sourceUrl}'), value: landmark.sourceUrl, groupValue: _selected,
              title: Text(landmark.name), subtitle: Text('${landmark.kind} · نحو ${landmark.distanceMetres} متر بخط مستقيم\nالمصدر: ${landmark.source} / OpenStreetMap · يحتاج مراجعتك'),
              onChanged: (value) => setState(() { _selected = value; _text.text = landmark.description; })),
            const SizedBox(height: 12),
            TextField(key: const ValueKey('landmark-description'), controller: _text, maxLength: 500, minLines: 2, maxLines: 4,
              onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'وصف قابل للتعديل (اختياري)')),
            if (widget.landmarks.isNotEmpty) const Text('© OpenStreetMap contributors · ODbL · Nominatim / Photon'),
          ])),
          const SizedBox(height: 12),
          AppButton(key: const ValueKey('landmark-apply'), label: 'استخدام النص بعد المراجعة', expand: true,
            onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text.trim())),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('متابعة دون إضافة وصف')),
        ])))));
}
