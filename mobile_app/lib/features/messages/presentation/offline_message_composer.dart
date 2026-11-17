import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/message_outbox.dart';
import 'pending_message_card.dart';

/// An offline property target is resolved and authorized by the server only
/// after connectivity returns. A queued bubble is never a delivery receipt.
class OfflineMessageComposer extends ConsumerStatefulWidget {
  const OfflineMessageComposer(
      {required this.target,
      required this.targetId,
      required this.title,
      super.key});
  final String target, title;
  final int targetId;
  @override
  ConsumerState<OfflineMessageComposer> createState() =>
      _OfflineMessageComposerState();
}

class _OfflineMessageComposerState
    extends ConsumerState<OfflineMessageComposer> {
  final _text = TextEditingController();
  late final int? _actor;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _actor = ref.read(authControllerProvider).asData?.value?.id;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _enqueue() async {
    if (_saving || _actor == null || _text.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(messageOutboxProvider(_actor).notifier)
          .enqueue(widget.target, widget.targetId, _text.text, label: widget.title);
      if (mounted) _text.clear();
    } catch (_) {
      if (mounted)
        { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر حفظ الرسالة. النص باقٍ؛ أعد المحاولة.'))); }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = _actor;
    if (actor == null)
      { return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.'))); }
    final rows = ref
        .watch(messageOutboxProvider(actor))
        .where(
            (m) => m.target == widget.target && m.targetId == widget.targetId)
        .toList();
    return ActorBoundPage(
        title: 'رسالة للمعلن',
        actorId: actor,
        builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
                appBar: AppBar(title: Text(widget.title)),
                body: Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'احفظ رسالتك هنا. تُرسل تلقائيًا عند عودة الاتصال إذا كانت المراسلة متاحة. تجد الرسائل المعلّقة أيضًا في «الرسائل».')),
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                        for (final message in rows)
                          PendingMessageCard(actor: actor, message: message)
                      ])),
                  SafeArea(
                      top: false,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: _text,
                                    enabled: !_saving,
                                    maxLength: 2000,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                        hintText: 'اكتب رسالة…'))),
                            IconButton(
                                onPressed: _saving ? null : _enqueue,
                                tooltip: 'حفظ للإرسال',
                                icon: const Icon(Icons.send)),
                          ]))),
                ]))));
  }
}
