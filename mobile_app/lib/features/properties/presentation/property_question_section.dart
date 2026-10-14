import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../discovery/data/ai_repository.dart';

class PropertyQuestionSection extends ConsumerStatefulWidget {
  const PropertyQuestionSection({required this.propertyId, super.key});
  final int propertyId;
  @override
  ConsumerState<PropertyQuestionSection> createState() => _PropertyQuestionState();
}
class _PropertyQuestionState extends ConsumerState<PropertyQuestionSection> {
  final _question = TextEditingController();
  String? _answer, _error;
  bool _busy = false;
  int _request = 0;
  @override
  void dispose() { _question.dispose(); super.dispose(); }
  @override
  void didUpdateWidget(PropertyQuestionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId) { _request++; _question.clear(); _answer = null; _error = null; _busy = false; }
  }
  Future<void> _ask() async {
    if (_busy || _question.text.trim().isEmpty) return;
    final request = ++_request;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await ref.read(aiRepositoryProvider).question(widget.propertyId, _question.text);
      final answer = result['answer'];
      if (answer is! String) throw StateError('Invalid answer.');
      if (mounted && request == _request) setState(() => _answer = answer);
    } catch (error) { if (mounted && request == _request) setState(() => _error = friendlyApiError(error)); }
    finally { if (mounted && request == _request) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => EbrokerSectionPanel(title: 'اسأل عن هذا العقار', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('الإجابة من بيانات الإعلان. التفاصيل غير المذكورة تحتاج سؤال المعلن.'), const SizedBox(height: 12),
    TextField(controller: _question, enabled: !_busy, maxLength: 800, minLines: 1, maxLines: 3,
      decoration: const InputDecoration(labelText: 'سؤالك', hintText: 'هل يوجد مصعد؟ ما المساحة؟'), onSubmitted: (_) => _ask()),
    AppButton(label: _busy ? 'جار قراءة بيانات الإعلان…' : 'عرض الإجابة', onPressed: _busy ? null : _ask),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: AppInlineMessage(message: _error!, tone: AppStatusTone.warning)),
    if (_answer != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_answer!)),
  ]));
}
