import 'dart:async';
import '../../../core/offline/offline_connection.dart';
import '../data/message_outbox.dart';
import 'pending_message_card.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/widgets/app_components.dart';
import '../../broker/presentation/broker_activity.dart';
import '../data/message_repository.dart';
import '../data/unread_inbox_repository.dart';
import '../../account/data/account_safety_repository.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../domain/message_models.dart';

class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({required this.threadId, this.compactPropertyContext = false, super.key});
  final int threadId;
  final bool compactPropertyContext;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return ActorBoundPage(title: 'المحادثة', builder: (_) =>
      _ConversationBody(key: ValueKey('$actor:$threadId'), threadId: threadId,
        compactPropertyContext: compactPropertyContext));
  }
}
class _ConversationBody extends ConsumerStatefulWidget {
  const _ConversationBody({required this.threadId, required this.compactPropertyContext, super.key});
  final int threadId;
  final bool compactPropertyContext;
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
  late final AccountRequestScope _scope;

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
    _scope = ref.read(accountRequestScopeProvider);
    ref.listenManual(messageDataRevisionProvider, (_, __) {
      if (mounted && _scope.isCurrent) Future.microtask(_load);
    });
    ref.listenManual(offlineResumeRevisionProvider, (_, __) {
      if (mounted && _scope.isCurrent) Future.microtask(_load);
    });
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_scope.isCurrent) return;
    final generation = ++_loadGeneration;
    setState(() { _loading = true; _error = null; });
    try {
      final details =
          await ref.read(messageRepositoryProvider).details(widget.threadId);
      if (!mounted || !_scope.isCurrent || generation != _loadGeneration)
        { return; }
      setState(() {
        _details = details;
        _loading = false;
        _error = null;
      });
      // Loading the newest page advances the server's read marker.
      ref.read(unreadInboxRevisionProvider.notifier).state++;
      // A received conversation must not wait for local outbox IO. The list
      // already hides pending rows whose client IDs are present in this receipt;
      // cleanup can finish independently without hiding authoritative messages.
      final actor = ref.read(authControllerProvider).asData?.value?.id;
      if (actor != null) {
        unawaited(ref.read(messageOutboxProvider(actor).notifier).reconcile(
            widget.threadId,
            details.messages
                .map((m) => m.clientMessageId)
                .whereType<String>()
                .toSet()).catchError((Object _) {}));
      }
    } catch (error) {
      if (!mounted || !_scope.isCurrent || generation != _loadGeneration) return;
      setState(() {
        if (!isTransientApiFailure(error)) _details = null;
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _loadOlder() async {
    if (!mounted || !_scope.isCurrent) return;
    final current = _details;
    final beforeId = current?.nextBeforeId;
    if (current == null || !current.hasMore || beforeId == null || _loadingOlder) {
      return;
    }
    final generation = _loadGeneration;
    setState(() => _loadingOlder = true);
    try {
      final older = await ref
          .read(messageRepositoryProvider)
          .details(widget.threadId, beforeId: beforeId);
      if (!mounted || !_scope.isCurrent || generation != _loadGeneration) return;
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
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    if (!mounted || !_scope.isCurrent) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _loading || _blocking || _error != null || _details?.thread.canSend != true) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null ) return;
    setState(() => _sending = true);
    try {
      await ref.read(messageOutboxProvider(actor).notifier)
          .enqueue('thread', widget.threadId, text, label: _details?.thread.otherUserName);
      if (!mounted || !_scope.isCurrent) return;
      _controller.clear();
    } catch (error) {
      if (mounted && _scope.isCurrent) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'تعذر حفظ الرسالة على الجهاز. النص باقٍ؛ أعد المحاولة.'))); }
        } finally {
      if (mounted && _scope.isCurrent) setState(() => _sending = false);
    }
  }


  Future<void> _callAdvertiser() async {
    if (!mounted || !_scope.isCurrent) return;
    if (_calling) return;
    setState(() => _calling = true);
    try {
      final call =
          await ref.read(messageRepositoryProvider).startExternalCall(widget.threadId);
      if (!mounted || !_scope.isCurrent) return;
      ref.read(messageDataRevisionProvider.notifier).state++;
      final uri = Uri(scheme: 'tel', path: call.phone);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح تطبيق الهاتف على هذا الجهاز.')),
        );
      }
      if (mounted && _scope.isCurrent) await _load();
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _calling = false);
    }
  }

  Future<void> _changeBlock() async {
    if (!mounted || !_scope.isCurrent) return;
    final thread = _details?.thread;
    if (thread == null || thread.otherUserId <= 0 || _blocking) return;
    final repo = ref.read(accountSafetyRepositoryProvider);
    final block = !thread.blockedByMe;
    final confirmed = await showActorDialog<bool>(context: context, ref: ref, builder: (dialog) => AlertDialog(
      scrollable: true, title: Text(block ? 'حظر هذا الحساب؟' : 'إلغاء الحظر؟'),
      content: Text(block ? 'ستتوقف الرسائل الجديدة بينكما. تبقى المحادثة السابقة وإمكانية البلاغ محفوظة.' : 'يمكن استئناف الرسائل الجديدة إذا كانت متاحة لدى الطرف الآخر.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(block ? 'حظر' : 'إلغاء الحظر'))]));
    if (confirmed != true || !mounted || !_scope.isCurrent) return;
    setState(() => _blocking = true);
    try {
      await repo.setBlocked(thread.otherUserId, block);
      if (!mounted || !_scope.isCurrent) return;
      ref.read(messageDataRevisionProvider.notifier).state++;
      await _load();
    } catch (error) {
      if (mounted && _scope.isCurrent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally { if (mounted && _scope.isCurrent) setState(() => _blocking = false); }
  }

  Widget _propertyContext(MessageThreadSummary thread) {
    final theme = Theme.of(context);
    final warning = theme.extension<AppSemanticColors>() ?? AppSemanticColors.light;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
        child: Row(
          children: [
            EbrokerIcon(Icons.home_work_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(
              thread.propertyTitle ?? 'العقار',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )),
            if (thread.isPropertyUnavailable) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'الإعلان غير متاح حاليًا. سجل المحادثة محفوظ.',
                child: Text('غير متاح', style: theme.textTheme.labelSmall?.copyWith(color: warning.warning)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _propertyAvailabilityBanner() {
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
    if (!mounted || !_scope.isCurrent) return;
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
    final accepted = await showActorDialog<bool>(
      context: context, ref: ref,
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
    if (accepted != true || !mounted || !_scope.isCurrent) return;
    if (text.length < 5) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.')));
      }
      return;
    }
    try {
      await ref
          .read(messageRepositoryProvider)
          .report(widget.threadId, reason: reason, details: text);
      if (!mounted || !_scope.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال البلاغ إلى الدعم.')));
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _details?.thread;
    final showPropertyContext = thread?.propertyId != null &&
        (widget.compactPropertyContext || thread?.canManageCustomer == true);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
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
          if (_details != null && (_loading || _error != null)) AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
          if (!_loading && thread?.canSend == false) Padding(padding: const EdgeInsets.all(12), child: Text(thread!.blockedByMe
            ? 'هذا الحساب محظور لديك. تبقى المحادثة السابقة محفوظة.' : 'الرسائل الجديدة غير متاحة حاليًا. يبقى تاريخ المحادثة والبلاغ متاحين.')),
          if (_blocking) const LinearProgressIndicator(),
          if (showPropertyContext) _propertyContext(thread!)
          else if (!_loading && thread?.isPropertyUnavailable == true) _propertyAvailabilityBanner(),
          if (!_loading && thread != null) BrokerConversationTools(thread: thread),
          Expanded(
              child: Container(
                decoration: const BoxDecoration(image: DecorationImage(
                  image: AssetImage('assets/ebroker/chat_background/doodle.png'),
                  repeat: ImageRepeat.repeat, opacity: 0.08)),
                child: _loading && _details == null
                  ? const AppLoadingState(label: 'جارٍ تحميل المحادثة…')
                  : _error != null && _details == null
                      ? AppErrorState(message: _error!, onRetry: _load)
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
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final pending = actor == null
        ? <PendingMessage>[]
        : ref
            .watch(messageOutboxProvider(actor))
            .where((m) =>
                (m.threadId == widget.threadId ||
                    m.target == 'thread' && m.targetId == widget.threadId) &&
                !messages.any((row) => row.clientMessageId == m.id))
            .toList()
            .reversed
            .toList();
    if (messages.isEmpty&& pending.isEmpty) return const Center(child: Text('ابدأ المحادثة برسالة محترمة وواضحة.'));
    final hasOlder = details?.hasMore == true;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(14),
      itemCount: pending.length + messages.length + (hasOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < pending.length)
          { return PendingMessageCard(actor: actor!, message: pending[index]); }
        index -= pending.length;
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
                    Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                color: item.isMine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                borderRadius: BorderRadius.circular(8)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.senderName,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12, color: item.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 4),
              Text(item.body, style: TextStyle(fontSize: 14, height: 1.3, color: item.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface)),
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: item.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
        );
      },
    );
  }
}
