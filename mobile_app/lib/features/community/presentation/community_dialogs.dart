import 'package:flutter/material.dart';

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
  });

  final String reason;
  final String details;
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
  required String label,
}) {
  return showDialog<CommunityReportDialogResult>(
    context: context,
    builder: (_) => _CommunityReportDialog(label: label),
  );
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
        FilledButton(
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
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _CommunityReportDialog extends StatefulWidget {
  const _CommunityReportDialog({required this.label});

  final String label;

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

  String _reason = 'misleading';
  late final TextEditingController _detailsController;
  String? _detailsError;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
  }

  @override
  void dispose() {
    _detailsController.dispose();
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
    Navigator.of(context).pop(
      CommunityReportDialogResult(reason: _reason, details: details),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('بلاغ عن ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _reason,
            decoration: const InputDecoration(labelText: 'السبب'),
            items: _reasons.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
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
              labelText: 'التفاصيل',
              hintText: 'اشرح سبب البلاغ بوضوح',
              errorText: _detailsError,
            ),
            onChanged: (_) {
              if (_detailsError != null) {
                setState(() => _detailsError = null);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('إرسال البلاغ'),
        ),
      ],
    );
  }
}
