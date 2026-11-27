import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_components.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../domain/listing_review_models.dart';
import 'review_protected_photo.dart';

class ReviewPhotoViewer extends ConsumerStatefulWidget {
  const ReviewPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.title = 'صورة الإعلان',
    this.canReject = false,
  });

  final List<ReviewMediaItem> photos;
  final int initialIndex;
  final String title;
  final bool canReject;

  @override
  ConsumerState<ReviewPhotoViewer> createState() => _ReviewPhotoViewerState();
}

class _ReviewPhotoViewerState extends ConsumerState<ReviewPhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.photos.length || !_pages.hasClients) return;
    _pages.animateToPage(index, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _reject(ReviewMediaItem photo) async {
    var note = photo.reviewReason ?? '';
    final form = GlobalKey<FormState>();
    final result = await showActorDialog<String>(
      ref: ref,
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('رفض الصورة'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: note,
            onChanged: (value) => note = value,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'سبب رفض الصورة'),
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? 'اكتب سببًا واضحًا من خمسة أحرف على الأقل.'
                : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialog, note.trim());
            },
            child: const Text('حفظ سبب الرفض'),
          ),
        ],
      ),
    );
    if (result != null && mounted) Navigator.pop(context, (photo, result));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Theme.of(context).colorScheme.primary,
      brightness: Brightness.dark,
    );
    final photo = widget.photos[_index];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: ThemeData(colorScheme: scheme, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'إغلاق الصورة',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.title),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Text('${arabicDigits('${_index + 1}')} من ${arabicDigits('${widget.photos.length}')}'),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.photos.length,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (_, index) => _ZoomableReviewPhoto(
                      key: ValueKey(widget.photos[index].id),
                      url: widget.photos[index].url,
                      onSwipe: (direction) => _goTo(index + direction),
                    ),
                  ),
                ),
                if (widget.photos.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'الصورة السابقة',
                        onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'الصورة التالية',
                        onPressed: _index == widget.photos.length - 1 ? null : () => _goTo(_index + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                if (photo.relevance == 'unrelated' || photo.relevance == 'uncertain')
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
                    child: Text(photo.reviewReason ?? 'تحتاج الصورة إلى مراجعة'),
                  ),
                if (widget.canReject && photo.relevanceToken != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error),
                        ),
                        onPressed: () => _reject(photo),
                        child: const Text('رفض الصورة'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomableReviewPhoto extends StatefulWidget {
  const _ZoomableReviewPhoto({super.key, required this.url, required this.onSwipe});
  final String url;
  final ValueChanged<int> onSwipe;

  @override
  State<_ZoomableReviewPhoto> createState() => _ZoomableReviewPhotoState();
}

class _ZoomableReviewPhotoState extends State<_ZoomableReviewPhoto> {
  final _scale = TransformationController();
  Offset _start = Offset.zero;
  Offset _current = Offset.zero;
  bool _singleFingerAtBase = false;

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _scale,
    minScale: 1,
    maxScale: 5,
    onInteractionStart: (details) {
      _start = _current = details.localFocalPoint;
      _singleFingerAtBase = details.pointerCount == 1 && _scale.value.getMaxScaleOnAxis() < 1.01;
    },
    onInteractionUpdate: (details) {
      _current = details.localFocalPoint;
      if (details.pointerCount > 1) _singleFingerAtBase = false;
    },
    onInteractionEnd: (_) {
      if (!_singleFingerAtBase || _scale.value.getMaxScaleOnAxis() >= 1.01) return;
      final delta = _current - _start;
      if (delta.dx.abs() >= 46 && delta.dx.abs() > delta.dy.abs() * 1.25) {
        widget.onSwipe(delta.dx > 0 ? 1 : -1);
      }
    },
    child: SizedBox.expand(child: ReviewProtectedPhoto(url: widget.url)),
  );
}
