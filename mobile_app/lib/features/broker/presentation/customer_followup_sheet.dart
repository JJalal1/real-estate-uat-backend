import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../messages/data/message_repository.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';

class CustomerStageChoices extends StatelessWidget {
  const CustomerStageChoices({required this.stage, required this.supportsClassification,
    required this.onSelected, super.key});

  final String stage;
  final bool supportsClassification;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final entry in brokerEditableLeadLabels.entries)
          ChoiceChip(
            key: ValueKey('customer-stage-${entry.key}'),
            label: Text(entry.value),
            selected: stage == entry.key,
            onSelected: supportsClassification || entry.key == 'not_interested'
                ? (selected) { if (selected) onSelected(entry.key); }
                : null,
          ),
        if (brokerEditableLeadLabels.containsKey(stage))
          TextButton(
            onPressed: () => onSelected('new'),
            child: const Text('إلغاء التصنيف'),
          ),
      ]),
      if (!supportsClassification)
        Text('تحديد الموعد والحجز يتطلبان تحديث الخادم.',
          style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

Future<bool> saveCustomerStage(BuildContext context, WidgetRef ref, int threadId, String stage) async {
  final scope = ref.read(accountRequestScopeProvider);
  try {
    await ref.read(brokerRepositoryProvider).updateCustomer(threadId, stage);
    if (!context.mounted || !scope.isCurrent) return false;
    ref.invalidate(brokerWorkspaceProvider);
    ref.read(messageDataRevisionProvider.notifier).state++;
    return true;
  } catch (error) {
    if (context.mounted && scope.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
    return false;
  }
}

String followupDateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.year}/${d.month}/${d.day} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<bool> editCustomerFollowup(BuildContext context, WidgetRef ref, int threadId, {BrokerCustomer? customer}) async {
  final scope = ref.read(accountRequestScopeProvider);
  final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
  bool current() => context.mounted && scope.isCurrent &&
      epoch == Stage6SecureSessionStore.instance.sessionEpoch;
  if (!current()) return false;
  var note = customer?.privateNote ?? '';
  var remindAt = customer?.remindAt;
  if (customer == null) {
    try {
      final data = await ref.read(brokerRepositoryProvider).followup(threadId);
      note = '${data['private_note'] ?? ''}';
      remindAt = DateTime.tryParse('${data['remind_at'] ?? ''}');
    } catch (error) {
      if (context.mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
      return false;
    }
  }
  if (!context.mounted || !current()) return false;
  return await showActorDialog<bool>(context: context, ref: ref,
    builder: (_) => _FollowupDialog(threadId: threadId, note: note, remindAt: remindAt)) ?? false;
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
  late final AccountRequestScope _scope;
  late final int _epoch;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    _epoch = Stage6SecureSessionStore.instance.sessionEpoch;
  }

  bool get _current => mounted && _scope.isCurrent &&
      _epoch == Stage6SecureSessionStore.instance.sessionEpoch;

  @override
  void dispose() { _note.dispose(); super.dispose(); }
  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 365));
    final saved = _date?.toLocal();
    final day = await showDatePicker(context: context,
      initialDate: saved != null && !saved.isBefore(now) && !saved.isAfter(end)
          ? saved : now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day), lastDate: end);
    if (day == null || !mounted || !_current) return;
    final time = await showTimePicker(context: context,
      initialTime: saved == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.fromDateTime(saved));
    if (time != null && _current) setState(() => _date = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }
  Future<void> _save() async {
    if (_busy || !_current) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(brokerRepositoryProvider).saveFollowup(widget.threadId, note: _note.text, remindAt: _date);
      if (!mounted || !_current) return;
      ref.invalidate(brokerWorkspaceProvider);
      Navigator.pop(context, true);
    } catch (error) { if (_current) setState(() { _error = friendlyApiError(error); _busy = false; }); }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final filled = FilledButton.styleFrom(
      backgroundColor: AppTheme.brand,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
    key: const ValueKey('broker-private-followup-dialog'),
    backgroundColor: dark ? const Color(0xff1d303b) : const Color(0xffe4f0f7),
    title: Text('متابعة العميل', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('الملاحظة والتذكير خاصان بحسابك.', style: theme.textTheme.bodySmall), const SizedBox(height: 12),
      TextField(key: const ValueKey('broker-private-note'), controller: _note,
        enabled: !_busy, minLines: 2, maxLines: 5, maxLength: 1500,
        decoration: InputDecoration(hintText: 'ملاحظة خاصة بك', filled: true, fillColor: scheme.surface)),
      const SizedBox(height: 10),
      FilledButton.icon(style: filled, label: const Text('ذكّرني غدًا'), icon: const Icon(Icons.event_outlined, size: 16),
        onPressed: _busy ? null : () { final day = DateTime.now().add(const Duration(days: 1)); setState(() => _date = DateTime(day.year, day.month, day.day, 9)); }),
      const SizedBox(height: 4),
      FilledButton.icon(style: filled, label: const Text('اختيار موعد'), icon: const Icon(Icons.schedule_outlined, size: 16),
        onPressed: _busy ? null : _chooseDate),
      if (_date != null) ...[const SizedBox(height: 10), Text('موعد المتابعة: ${followupDateLabel(_date!)}'),
        TextButton.icon(onPressed: _busy ? null : () => setState(() => _date = null), icon: const EbrokerIcon(Icons.check_circle_outline, size: 18), label: const Text('إنهاء التذكير'))],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('رجوع')),
      AppButton(label: 'حفظ المتابعة', loading: _busy, onPressed: _busy ? null : _save)],
    ));
  }
}
