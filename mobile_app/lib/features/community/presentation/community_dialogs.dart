import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/presentation/actor_scoped_page.dart';

class CommunityRatingDialogResult {
  const CommunityRatingDialogResult({
    required this.rating,
    required this.comment,
  });

  final int rating;
  final String? comment;
}

class CommunityReportDialogResult {
  const CommunityReportDialogResult({
    required this.reason,
    required this.details,
    this.attachment,
  });

  final String reason;
  final String details;
  final String? attachment;
}

Future<String?> showCommunityTextDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CommunityTextDialog(
      title: title,
      hint: hint,
      initial: initial,
    ),
  );
}

Future<CommunityRatingDialogResult?> showAdvertiserRatingDialog(
  BuildContext context, {
  required int initialRating,
  String initialComment = '',
}) {
  return showDialog<CommunityRatingDialogResult>(
    context: context,
    builder: (_) => _AdvertiserRatingDialog(
      initialRating: initialRating,
      initialComment: initialComment,
    ),
  );
}

Future<CommunityReportDialogResult?> showCommunityReportDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String label,
  String? target,
  String? property,
  bool conversation = false,
}) async {
  String? submittedAttachment;
  final result = await showActorDialog<CommunityReportDialogResult>(
    context: context,
    ref: ref,
    builder: (_) => _CommunityReportDialog(
      label: label,
      target: target,
      property: property,
      conversation: conversation,
      onSubmitAttachment: (path) => submittedAttachment = path,
    ),
  );
  if (result == null) await clearReportEvidence(submittedAttachment);
  return result;
}

Future<void> showReportReceipt(BuildContext context, {required WidgetRef ref,
    required int caseId, String? reference,
    bool alreadyReceived = false}) async {
  final follow = await showActorDialog<bool>(context: context, ref: ref, builder: (dialog) => AlertDialog(
    title: Text(alreadyReceived ? 'وصل بلاغك سابقًا' : 'وصل بلاغك للدعم'),
    content: reference == null || reference.isEmpty ? null : Text('رقم البلاغ $reference'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إغلاق')),
      if (caseId > 0)
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('متابعة البلاغ')),
    ],
  ));
  if (context.mounted && follow == true) await context.push<void>('/support?case=$caseId');
}

Future<void> clearReportEvidence(String? path) async {
  if (path == null) return;
  try { await const Stage5MediaPicker().clearTemporaryFiles([path]); } catch (_) { /* Temporary file. */ }
}

class _CommunityTextDialog extends StatefulWidget {
  const _CommunityTextDialog({
    required this.title,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String hint;
  final String initial;

  @override
  State<_CommunityTextDialog> createState() => _CommunityTextDialogState();
}

class _CommunityTextDialogState extends State<_CommunityTextDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length < 2) {
      setState(() => _errorText = 'اكتب حرفين على الأقل.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 5,
        maxLength: 1500,
        decoration: InputDecoration(
          hintText: widget.hint,
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        EbrokerFilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _AdvertiserRatingDialog extends StatefulWidget {
  const _AdvertiserRatingDialog({
    required this.initialRating,
    required this.initialComment,
  });

  final int initialRating;
  final String initialComment;

  @override
  State<_AdvertiserRatingDialog> createState() =>
      _AdvertiserRatingDialogState();
}

class _AdvertiserRatingDialogState extends State<_AdvertiserRatingDialog> {
  late int _rating;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating < 1
        ? 1
        : widget.initialRating > 5
            ? 5
            : widget.initialRating;
    _controller = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final comment = _controller.text.trim();
    Navigator.of(context).pop(
      CommunityRatingDialogResult(
        rating: _rating,
        comment: comment.isEmpty ? null : comment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تقييم المعلن'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            value: _rating,
            decoration: const InputDecoration(labelText: 'التقييم'),
            items: List.generate(
              5,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1} / 5'),
              ),
            ),
            onChanged: (next) {
              if (next != null) {
                setState(() => _rating = next);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ملاحظة اختيارية',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        EbrokerFilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _CommunityReportDialog extends StatefulWidget {
  const _CommunityReportDialog({required this.label, required this.conversation,
    required this.onSubmitAttachment, this.target, this.property});

  final String label;
  final bool conversation;
  final String? target;
  final String? property;
  final ValueChanged<String?> onSubmitAttachment;

  @override
  State<_CommunityReportDialog> createState() => _CommunityReportDialogState();
}

class _CommunityReportDialogState extends State<_CommunityReportDialog> {
  static const _reasons = <String, String>{
    'spam': 'محتوى مزعج',
    'fraud': 'احتيال أو تضليل خطير',
    'abuse': 'إساءة',
    'misleading': 'معلومات مضللة',
    'duplicate': 'مكرر',
    'privacy': 'خصوصية',
    'other': 'سبب آخر',
  };

  late String _reason;
  String? _attachment;
  bool _submitted = false;
  late final TextEditingController _detailsController;
  String? _detailsError;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    _reason = widget.conversation ? 'abuse' : 'misleading';
  }

  @override
  void dispose() {
    _detailsController.dispose();
    if (!_submitted) clearReportEvidence(_attachment).ignore();
    super.dispose();
  }

  void _submit() {
    final details = _detailsController.text.trim();
    if (details.length < 5) {
      setState(
        () => _detailsError = 'اكتب تفاصيل واضحة لا تقل عن 5 أحرف.',
      );
      return;
    }
    _submitted = true;
    widget.onSubmitAttachment(_attachment);
    Navigator.of(context).pop(
      CommunityReportDialogResult(reason: _reason, details: details, attachment: _attachment),
    );
  }

  Future<void> _pick() async {
    try {
      final selected = await const Stage5MediaPicker().pickSupportEvidence();
      if (selected == null) return;
      if (!mounted) { await clearReportEvidence(selected); return; }
      clearReportEvidence(_attachment).ignore();
      setState(() => _attachment = selected);
    } catch (_) {
      if (mounted) setState(() => _detailsError = 'تعذّر إرفاق الملف.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = {..._reasons};
    if (widget.conversation) {
      reasons.remove('duplicate');
      reasons.remove('misleading');
      reasons['harassment'] = 'مضايقة';
    }
    return AlertDialog(
      scrollable: true,
      title: Text('بلاغ عن ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.target case final name?) ListTile(contentPadding: EdgeInsets.zero,
            title: Text(name), subtitle: widget.property == null ? null : Text(widget.property!)),
          DropdownButtonFormField<String>(
            value: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'السبب'),
            items: reasons.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                setState(() => _reason = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detailsController,
            maxLines: 4,
            maxLength: 5000,
            decoration: InputDecoration(
              labelText: 'وش حصل؟',
              errorText: _detailsError,
            ),
            onChanged: (_) {
              if (_detailsError != null) {
                setState(() => _detailsError = null);
              }
            },
          ),
          TextButton.icon(icon: const Icon(Icons.attach_file),
            label: Text(_attachment == null ? 'إرفاق دليل' : 'استبدال المرفق'), onPressed: _pick),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        EbrokerFilledButton(
          onPressed: _submit,
          child: const Text('إرسال البلاغ'),
        ),
      ],
    );
  }
}
