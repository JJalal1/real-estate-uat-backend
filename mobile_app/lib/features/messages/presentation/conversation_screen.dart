import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking_models.dart';
import '../../bookings/presentation/booking_request_sheet.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.threadId, super.key});
  final int threadId;
  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _controller = TextEditingController();
  MessageThreadDetails? _details;
  ViewingBooking? _viewing;
  bool _loading = true;
  bool _sending = false;
  bool _bookingBusy = false;
  String? _error;
  String? _pendingMessageKey;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final details =
          await ref.read(messageRepositoryProvider).details(widget.threadId);
      ViewingBooking? viewing;
      try {
        final bookings = await ref.read(bookingRepositoryProvider).mine();
        for (final booking in bookings) {
          if (booking.messageThreadId == widget.threadId) {
            viewing = booking;
            if (booking.isActive) break;
          }
        }
      } catch (_) {
        // Messaging remains usable if the booking refresh is temporarily unavailable.
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _viewing = viewing;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final key = _pendingMessageKey ??
        'm-${widget.threadId}-${DateTime.now().microsecondsSinceEpoch}';
    _pendingMessageKey = key;
    setState(() => _sending = true);
    try {
      await ref.read(messageRepositoryProvider).send(widget.threadId, text,
          clientMessageId: key);
      ref.read(messageDataRevisionProvider.notifier).state++;
      _controller.clear();
      _pendingMessageKey = null;
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${friendlyApiError(error)} يمكنك الضغط على إرسال مرة أخرى بأمان.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _bookingAction(String action) async {
    final booking = _viewing;
    if (booking == null || _bookingBusy) return;
    setState(() => _bookingBusy = true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      ViewingBooking? updated;
      if (action == 'confirm') {
        updated = await repo.confirm(booking.id);
      } else if (action == 'decline') {
        final reason = await _bookingReason('رفض طلب المعاينة', 'سبب الرفض');
        if (reason == null) return;
        updated = await repo.decline(booking.id, reason);
      } else if (action == 'cancel') {
        final reason = await _bookingReason('إلغاء المعاينة', 'سبب الإلغاء');
        if (reason == null) return;
        updated = await repo.cancel(booking.id, reason);
      } else if (action == 'reschedule') {
        if (!mounted) return;
        updated = await BookingRequestSheet.showForReschedule(context, booking);
        if (updated == null) return;
      } else if (action == 'complete') {
        updated = await repo.complete(booking.id);
      }
      if (!mounted || updated == null) return;
      setState(() => _viewing = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث حالة طلب المعاينة.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _bookingBusy = false);
    }
  }

  Future<String?> _bookingReason(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 1500,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().length < 2) return null;
    return result.trim();
  }

  Widget _viewingCard(ViewingBooking booking) {
    final start = booking.startsAt.toLocal();
    final date =
        "${start.year}/${start.month.toString().padLeft(2, '0')}/${start.day.toString().padLeft(2, '0')} - ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.event_available_outlined),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('طلب معاينة مرتبط بهذه المحادثة',
                      style: TextStyle(fontWeight: FontWeight.w900))),
              Chip(label: Text(booking.statusLabel)),
            ]),
            Text(date),
            const SizedBox(height: 4),
            Text(booking.isRequester
                ? 'المعلن: ${booking.hostName ?? '-'}'
                : 'طالب المعاينة: ${booking.requesterName}'),
            if (booking.awaitingRequesterConfirmation && booking.isRequester)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('المعلن اقترح هذا الموعد الجديد. راجعه ثم وافق عليه أو غيّره.'),
              ),
            if (booking.requesterNote?.trim().isNotEmpty == true)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('ملاحظة الطلب: ${booking.requesterNote}')),
            if (booking.hostNote?.trim().isNotEmpty == true)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('ملاحظة المعلن: ${booking.hostNote}')),
            if (booking.isActive) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (booking.canConfirm)
                  FilledButton.tonalIcon(
                    onPressed:
                        _bookingBusy ? null : () => _bookingAction('confirm'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(booking.canAcceptReschedule
                        ? 'قبول الموعد الجديد'
                        : 'تأكيد الموعد'),
                  ),
                if (booking.canDecline)
                  OutlinedButton.icon(
                    onPressed:
                        _bookingBusy ? null : () => _bookingAction('decline'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('رفض'),
                  ),
                if (booking.canReschedule)
                  OutlinedButton.icon(
                    onPressed: _bookingBusy
                        ? null
                        : () => _bookingAction('reschedule'),
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('تغيير الموعد'),
                  ),
                if (booking.canCancel)
                  OutlinedButton.icon(
                    onPressed:
                        _bookingBusy ? null : () => _bookingAction('cancel'),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('إلغاء'),
                  ),
              ]),
            ],
            if (booking.canComplete) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                  onPressed:
                      _bookingBusy ? null : () => _bookingAction('complete'),
                  icon: const Icon(Icons.task_alt),
                  label: const Text('تسجيل المعاينة كمكتملة')),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _report() async {
    const reasons = <String, String>{
      'abuse': 'إساءة',
      'fraud': 'احتيال',
      'privacy': 'خصوصية',
      'harassment': 'مضايقة',
      'spam': 'إزعاج',
      'other': 'أخرى'
    };
    var reason = 'abuse';
    final details = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('بلاغ عن المحادثة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('لن يفتح فريق الدعم محتوى المحادثة إلا ضمن هذا البلاغ وبصلاحية فتح المحادثات الخاصة، وسيتم تسجيل عملية الفتح.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                value: reason,
                items: reasons.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => reason = value);
                }),
            const SizedBox(height: 12),
            TextField(
                controller: details,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: 'تفاصيل البلاغ')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إرسال البلاغ')),
          ],
        ),
      ),
    );
    final text = details.text.trim();
    details.dispose();
    if (accepted != true) return;
    if (text.length < 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.')));
      }
      return;
    }
    try {
      await ref
          .read(messageRepositoryProvider)
          .report(widget.threadId, reason: reason, details: text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال البلاغ إلى الدعم.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
            title: Text(_details?.thread.otherUserName ?? 'محادثة'),
            actions: [
              IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  onPressed: _report,
                  tooltip: 'بلاغ',
                  icon: const Icon(Icons.flag_outlined))
            ]),
        body: Column(children: [
          if (!_loading && _viewing != null) _viewingCard(_viewing!),
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _messageList()),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration:
                                const InputDecoration(hintText: 'اكتب رسالة...'),
                            onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send)),
                  ]))),
        ]),
      ),
    );
  }

  Widget _messageList() {
    final messages = _details?.messages ?? const <PrivateMessageItem>[];
    if (messages.isEmpty) {
      return const Center(child: Text('ابدأ المحادثة برسالة محترمة وواضحة.'));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(14),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final item = messages[messages.length - 1 - index];
        return Align(
          alignment: item.isMine
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.senderName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 4),
              Text(item.body),
            ]),
          ),
        );
      },
    );
  }
}
