import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/message_outbox.dart';

class PendingMessageCard extends ConsumerWidget {
  const PendingMessageCard(
      {required this.actor,
      required this.message,
      this.showTarget = false,
      super.key});
  final int actor;
  final PendingMessage message;
  final bool showTarget;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = switch (message.status) {
      'sent' => 'أُرسلت',
      'sending' => 'جارٍ الإرسال…',
      'failed' => message.error ?? 'لم تُرسل',
      _ => 'معلّقة — تُرسل عند عودة الاتصال',
    };
    Future<void> action(bool retry) async {
      try {
        final box = ref.read(messageOutboxProvider(actor).notifier);
        if (retry) {
          await box.retry(message.id);
        } else {
          await box.cancel(message.id);
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تعذر تحديث الرسالة المحفوظة. أعد المحاولة.')));
        }
      }
    }

    return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Card(
            key: ValueKey('outbox-${message.id}'),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showTarget)
                        Text(message.label ?? 'رسالة للمعلن',
                            style: Theme.of(context).textTheme.labelSmall),
                      Text(message.body),
                      const SizedBox(height: 4),
                      Text(status,
                          style: Theme.of(context).textTheme.labelSmall),
                      if (message.status != 'sending' &&
                          message.status != 'sent')
                        Wrap(children: [
                          if (message.status == 'failed')
                            TextButton(
                                onPressed: () => action(true),
                                child: const Text('إعادة المحاولة')),
                          TextButton(
                              onPressed: () => action(false),
                              child: const Text('إلغاء الإرسال')),
                        ]),
                    ]))));
  }
}
