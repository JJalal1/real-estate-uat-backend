import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';

String followupDateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.year}/${d.month}/${d.day} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<bool> editCustomerFollowup(BuildContext context, WidgetRef ref, int threadId, {BrokerCustomer? customer}) async {
  var note = customer?.privateNote ?? '';
  var remindAt = customer?.remindAt;
  if (customer == null) {
    try {
      final data = await ref.read(brokerRepositoryProvider).followup(threadId);
      note = '${data['private_note'] ?? ''}';
      remindAt = DateTime.tryParse('${data['remind_at'] ?? ''}');
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      return false;
    }
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(context: context, builder: (_) => _FollowupDialog(threadId: threadId, note: note, remindAt: remindAt)) ?? false;
}

class _FollowupDialog extends ConsumerStatefulWidget {
  const _FollowupDialog({required this.threadId, required this.note, this.remindAt});
  final int threadId;
  final String note;
  final DateTime? remindAt;
  @override
  ConsumerState<_FollowupDialog> createState() => _FollowupDialogState();
}
class _FollowupDialogState extends ConsumerState<_FollowupDialog> {
  late final _note = TextEditingController(text: widget.note);
  late DateTime? _date = widget.remindAt;
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _note.dispose(); super.dispose(); }
  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: _date?.isAfter(now) == true ? _date! : now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time != null && mounted) setState(() => _date = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }
  Future<void> _save() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(brokerRepositoryProvider).saveFollowup(widget.threadId, note: _note.text, remindAt: _date);
      ref.invalidate(brokerWorkspaceProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) { if (mounted) setState(() { _error = friendlyApiError(error); _busy = false; }); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('متابعة العميل'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('الملاحظة والتذكير خاصان بحسابك.'), const SizedBox(height: 12),
      TextField(controller: _note, minLines: 2, maxLines: 5, maxLength: 1500, decoration: const InputDecoration(labelText: 'ملاحظة خاصة بك')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppButton(label: 'ذكّرني غدًا', icon: Icons.event_outlined, onPressed: _busy ? null : () { final day = DateTime.now().add(const Duration(days: 1)); setState(() => _date = DateTime(day.year, day.month, day.day, 9)); }),
        AppButton(label: 'اختيار موعد', icon: Icons.schedule_outlined, onPressed: _busy ? null : _chooseDate),
      ]),
      if (_date != null) ...[const SizedBox(height: 10), Text('موعد المتابعة: ${followupDateLabel(_date!)}'),
        TextButton.icon(onPressed: _busy ? null : () => setState(() => _date = null), icon: const EbrokerIcon(Icons.check_circle_outline, size: 18), label: const Text('إنهاء التذكير'))],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('رجوع')),
      AppButton(label: 'حفظ المتابعة', loading: _busy, onPressed: _busy ? null : _save)],
  );
}
