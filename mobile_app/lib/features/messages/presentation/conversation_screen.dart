import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/theme/ebroker_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_error_message.dart';
import '../../broker/presentation/broker_activity.dart';
import '../data/message_repository.dart';
import '../../account/data/account_safety_repository.dart';
import '../../account/data/auth_controller.dart';
import '../domain/message_models.dart';

class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({required this.threadId, super.key});
  final int threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _ConversationBody(key: ValueKey('$actor:$threadId'), threadId: threadId);
  }
}
class _ConversationBody extends ConsumerStatefulWidget {
  const _ConversationBody({required this.threadId, super.key});
  final int threadId;
  @override
  ConsumerState<_ConversationBody> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<_ConversationBody> {
  final _controller = TextEditingController();
  MessageThreadDetails? _details;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _calling = false;
  bool _blocking = false;
  int _loadGeneration = 0;
  String? _error;
  String? _pendingMessageKey;
  String? _pendingMessageText;

  void _chooseQuickReply(String text) {
    if (_sending) return;
    final current = _controller.text.trim();
    final candidate = current.isEmpty ? text : '$current\n$text';
    if (candidate.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختصر الرسالة الحالية قبل إضافة الرد السريع.'))); return;
    }
    _controller.value = TextEditingValue(text: candidate, selection: TextSelection.collapsed(offset: candidate.length));
  }

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
    final generation = ++_loadGeneration;
    try {
      final details =
          await ref.read(messageRepositoryProvider).details(widget.threadId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _details = details;
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

  Future<void> _loadOlder() async {
    final current = _details;
    final beforeId = current?.nextBeforeId;
    if (current == null || !current.hasMore || beforeId == null || _loadingOlder) {
      return;
    }
    setState(() => _loadingOlder = true);
    try {
      final older = await ref
          .read(messageRepositoryProvider)
          .details(widget.threadId, beforeId: beforeId);
      if (!mounted) return;
      final byId = <int, PrivateMessageItem>{
        for (final item in older.messages) item.id: item,
        for (final item in current.messages) item.id: item,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      setState(() {
        _details = MessageThreadDetails(
          thread: current.thread,
          messages: merged,
          hasMore: older.hasMore,
          nextBeforeId: older.nextBeforeId,
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _details?.thread.canSend != true) return;
    if (_pendingMessageText != null && _pendingMessageText != text) {
      _pendingMessageKey = null;
    }
    final key = _pendingMessageKey ??
        'm-${widget.threadId}-${DateTime.now().microsecondsSinceEpoch}';
    _pendingMessageKey = key;
    _pendingMessageText = text;
    setState(() => _sending = true);
    try {
      await ref.read(messageRepositoryProvider).send(widget.threadId, text,
          clientMessageId: key);
      if (!mounted) return;
      ref.read(messageDataRevisionProvider.notifier).state++;
      _controller.clear();
      _pendingMessageKey = null;
      _pendingMessageText = null;
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${friendlyApiError(error)} يمكنك إعادة الإرسال بأمان ما دام النص لم يتغير.')));
        if (error is DioException && error.response?.statusCode == 403) await _load();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  Future<void> _callAdvertiser() async {
    if (_calling) return;
    setState(() => _calling = true);
    try {
      final call =
          await ref.read(messageRepositoryProvider).startExternalCall(widget.threadId);
      ref.read(messageDataRevisionProvider.notifier).state++;
      final uri = Uri(scheme: 'tel', path: call.phone);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح تطبيق الهاتف على هذا الجهاز.')),
        );
      }
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  Future<void> _changeBlock() async {
    final thread = _details?.thread;
    if (thread == null || thread.otherUserId <= 0 || _blocking) return;
    final repo = ref.read(accountSafetyRepositoryProvider);
    final block = !thread.blockedByMe;
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      scrollable: true, title: Text(block ? 'حظر هذا الحساب؟' : 'إلغاء الحظر؟'),
      content: Text(block ? 'ستتوقف الرسائل الجديدة بينكما. تبقى المحادثة السابقة وإمكانية البلاغ محفوظة.' : 'يمكن استئناف الرسائل الجديدة إذا كانت متاحة لدى الطرف الآخر.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(block ? 'حظر' : 'إلغاء الحظر'))]));
    if (confirmed != true || !mounted) return;
    setState(() => _blocking = true);
    try {
      await repo.setBlocked(thread.otherUserId, block);
      if (!mounted) return;
      ref.read(messageDataRevisionProvider.notifier).state++;
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally { if (mounted) setState(() => _blocking = false); }
  }

  Widget _propertyAvailabilityBanner(MessageThreadSummary thread) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EbrokerIcon(Icons.info_outline),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'هذا الإعلان لم يعد منشوراً. تبقى المحادثة وسجلها متاحين للتنسيق، لكن لا تعتمد على الإعلان كعرض متاح حالياً.',
              ),
            ),
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
            EbrokerFilledButton(
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
    final thread = _details?.thread;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: EbrokerDesign.page,
        appBar: AppBar(
            title: Text(thread?.otherUserName ?? 'محادثة'),
            actions: [
              if (thread?.canCallAdvertiser == true)
                IconButton(
                    onPressed: _calling ? null : _callAdvertiser,
                    tooltip: 'اتصال بالمعلن',
                    icon: _calling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const EbrokerIcon(Icons.phone_outlined)),
              IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'تحديث',
                  icon: const EbrokerIcon(Icons.refresh)),
              IconButton(
                  onPressed: _loading ? null : _report,
                  tooltip: 'بلاغ',
                  icon: const EbrokerIcon(Icons.flag_outlined)),
              if (thread != null && thread.otherUserId > 0) PopupMenuButton<String>(tooltip: 'خيارات المحادثة', enabled: !_blocking,
                onSelected: (_) => _changeBlock(), itemBuilder: (_) => [PopupMenuItem(value: 'block', child: Text(thread.blockedByMe ? 'إلغاء الحظر' : 'حظر الحساب'))]),
            ]),
        body: Column(children: [
          if (!_loading && thread?.canSend == false) Padding(padding: const EdgeInsets.all(12), child: Text(thread!.blockedByMe
            ? 'هذا الحساب محظور لديك. تبقى المحادثة السابقة محفوظة.' : 'الرسائل الجديدة غير متاحة حاليًا. يبقى تاريخ المحادثة والبلاغ متاحين.')),
          if (_blocking) const LinearProgressIndicator(),
          if (!_loading && thread?.isPropertyUnavailable == true) _propertyAvailabilityBanner(thread!),
          if (!_loading && thread != null) BrokerConversationTools(thread: thread),
          Expanded(
              child: Container(
                decoration: const BoxDecoration(image: DecorationImage(
                  image: AssetImage('assets/ebroker/chat_background/doodle.png'),
                  repeat: ImageRepeat.repeat, opacity: 0.08)),
                child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _messageList())),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    PopupMenuButton<String>(tooltip: 'ردود سريعة', enabled: !_sending && !_loading && _error == null && thread?.canSend == true,
                      icon: const EbrokerIcon(Icons.quickreply_outlined, size: 22),
                      onSelected: _chooseQuickReply,
                      itemBuilder: (_) => [
                        if (thread?.canManageCustomer == true && thread?.isPropertyUnavailable != true) const PopupMenuItem(value: 'العقار متاح حاليًا. هل يناسبك تحديد موعد للمعاينة؟', child: Text('العقار متاح')),
                        const PopupMenuItem(value: 'متى يناسبك موعد المعاينة؟', child: Text('تنسيق زيارة العقار')),
                        const PopupMenuItem(value: 'شكرًا لتواصلك. سأراجع التفاصيل وأرد عليك.', child: Text('سأرد عليك')),
                        const PopupMenuItem(value: 'شكرًا لك. هل ما زلت مهتمًا بهذا العقار؟', child: Text('متابعة الاهتمام')),
                      ]),
                    Expanded(
                        child: TextField(
                            controller: _controller,
                            enabled: thread?.canSend == true && !_sending && !_blocking,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration:
                                const InputDecoration(hintText: 'اكتب رسالة...'),
                            onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        style: IconButton.styleFrom(fixedSize: const Size(46, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                        onPressed: _sending || _blocking || _error != null || thread?.canSend != true ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const EbrokerIcon(Icons.send)),
                  ]))),
        ]),
      ),
    );
  }

  Widget _messageList() {
    final details = _details;
    final messages = details?.messages ?? const <PrivateMessageItem>[];
    if (messages.isEmpty) {
      return const Center(child: Text('ابدأ المحادثة برسالة محترمة وواضحة.'));
    }
    final hasOlder = details?.hasMore == true;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(14),
      itemCount: messages.length + (hasOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasOlder && index == messages.length) {
          return Center(
            child: TextButton.icon(
              onPressed: _loadingOlder ? null : _loadOlder,
              icon: _loadingOlder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const EbrokerIcon(Icons.history),
              label: const Text('تحميل رسائل أقدم'),
            ),
          );
        }
        final item = messages[messages.length - 1 - index];
        final createdAt = item.createdAt?.toLocal();
        final time = createdAt == null
            ? null
            : '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
        if (item.isCallStarted) {
          return Align(
            alignment: AlignmentDirectional.center,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EbrokerIcon(Icons.phone_in_talk_outlined, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.isMine
                          ? 'بدأت اتصالاً بالمعلن'
                          : '${item.senderName} بدأ اتصالاً هاتفياً',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (time != null) ...[
                    const SizedBox(width: 8),
                    Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: item.isMine ? Colors.white : EbrokerDesign.textLight)),
                  ],
                ],
              ),
            ),
          );
        }
        return Align(
          alignment: item.isMine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: item.isMine ? Theme.of(context).colorScheme.primary : Colors.white,
                border: Border.all(color: EbrokerDesign.border, width: 1.5),
                borderRadius: BorderRadius.circular(8)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.senderName,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12, color: item.isMine ? Colors.white : EbrokerDesign.text)),
              const SizedBox(height: 4),
              Text(item.body, style: TextStyle(fontSize: 14, height: 1.3, color: item.isMine ? Colors.white : EbrokerDesign.text)),
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: item.isMine ? Colors.white : EbrokerDesign.textLight)),
              ],
            ]),
          ),
        );
      },
    );
  }
}
