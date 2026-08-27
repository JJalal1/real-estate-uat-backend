import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
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
  bool _loading = true;
  bool _sending = false;
  String? _error;

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
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(messageRepositoryProvider).send(widget.threadId, text);
      ref.read(messageDataRevisionProvider.notifier).state++;
      _controller.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
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
            const Text(
                'لن يفتح فريق الدعم محتوى المحادثة إلا ضمن هذا البلاغ وبصلاحية فتح المحادثات الخاصة، وسيتم تسجيل عملية الفتح.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                value: reason,
                items: reasons.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => reason = value);
                  }
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
    if (accepted != true) {
      return;
    }
    if (text.length < 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.'),
          ),
        );
      }
      return;
    }
    try {
      await ref
          .read(messageRepositoryProvider)
          .report(widget.threadId, reason: reason, details: text);
      if (!mounted) {
        return;
      }
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
                  onPressed: _report,
                  tooltip: 'بلاغ',
                  icon: const Icon(Icons.flag_outlined))
            ]),
        body: Column(children: [
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
                            decoration: const InputDecoration(
                                hintText: 'اكتب رسالة...'),
                            onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send)),
                  ]))),
        ]),
      ),
    );
  }

  Widget _messageList() {
    final messages = _details?.messages ?? const <PrivateMessageItem>[];
    if (messages.isEmpty) {
      return const Center(
        child: Text('ابدأ المحادثة برسالة محترمة وواضحة.'),
      );
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
