import 'dart:async';
import '../../../core/offline/offline_connection.dart';
import '../data/message_outbox.dart';
import 'pending_message_card.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/messaging_system_navigation.dart';
import '../../../core/widgets/app_components.dart';
import '../../broker/data/broker_repository.dart';
import '../../broker/presentation/broker_activity.dart';
import '../data/message_repository.dart';
import '../data/message_typing_repository.dart';
import '../data/unread_inbox_repository.dart';
import '../../community/presentation/community_dialogs.dart';
import '../../account/data/account_safety_repository.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../domain/message_models.dart';
import 'conversation_typing_session.dart';

class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({required this.threadId, super.key});
  final int threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    return ActorBoundPage(title: 'المحادثة', builder: (_) =>
      _ConversationBody(key: ValueKey('${user?.id}:$threadId'), threadId: threadId));
  }
}
class _ConversationBody extends ConsumerStatefulWidget {
  const _ConversationBody({required this.threadId, super.key});
  final int threadId;
  @override
  ConsumerState<_ConversationBody> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<_ConversationBody> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _composerFocus = FocusNode();
  MessageThreadDetails? _details;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _calling = false;
  bool _blocking = false;
  int _loadGeneration = 0;
  String? _error;
  late final AccountRequestScope _scope;
  late final ConversationTypingSession _typing;
  bool _foreground = false;
  bool _routeCurrent = false;
  bool _peerTyping = false;
  bool _closing = false;

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
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final threadId = widget.threadId;
    final typingRepository = ref.read(messageTypingRepositoryProvider);
    _typing = ConversationTypingSession(
      readPeer: () => typingRepository.read(threadId),
      setTyping: (typing) => typingRepository.setTyping(threadId, typing),
      isCurrent: () => _scope.isCurrent && epoch == Stage6SecureSessionStore.instance.sessionEpoch,
      onPeerChanged: (typing) {
        if (mounted && !_closing) setState(() => _peerTyping = typing);
      },
    );
    _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _composerFocus.addListener(() {
      if (!_composerFocus.hasFocus) _typing.stop();
    });
    ref.listenManual(messageDataRevisionProvider, (_, __) {
      if (mounted && _scope.isCurrent) Future.microtask(_load);
    });
    ref.listenManual(offlineResumeRevisionProvider, (_, __) {
      if (mounted && _scope.isCurrent) Future.microtask(_load);
    });
    ref.listenManual(offlineConnectionProvider, (_, __) => _syncTypingAvailability());
    Future.microtask(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _syncTypingAvailability();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTypingAvailability();
  }

  void _syncTypingAvailability() {
    _typing.setActive(_foreground && _routeCurrent && _scope.isCurrent &&
        _details?.thread.canSend == true && _error == null &&
        ref.read(offlineConnectionProvider) == OfflineConnection.online);
  }

  @override
  void dispose() {
    _closing = true;
    _typing.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _composerFocus.dispose();
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
      _syncTypingAvailability();
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
      _syncTypingAvailability();
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
    _typing.stop();
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

  Future<void> _report(MessageThreadSummary thread) async {
    if (!mounted || !_scope.isCurrent) return;
    final input = await showCommunityReportDialog(context, label: 'المحادثة',
      target: thread.otherUserName, property: thread.propertyTitle, conversation: true);
    if (input == null) return;
    try {
      if (!mounted || !_scope.isCurrent) return;
      final report = await ref.read(messageRepositoryProvider).report(widget.threadId,
        reason: input.reason, details: input.details, attachment: input.attachment);
      if (mounted && _scope.isCurrent) {
        await showReportReceipt(context,
        caseId: report.supportCaseId ?? 0, reference: report.reference);
      }
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      await clearReportEvidence(input.attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _details?.thread;
    final dealData = thread?.propertyId != null
        ? ref.watch(brokerThreadDealProvider(thread!.id)).asData : null;
    final deal = dealData?.value;
    final mayRecordDeal = dealData != null && deal == null &&
        thread?.canManageCustomer == true && thread?.leadStage != 'completed';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: AppBar(
            title: Text(thread?.otherUserName ?? 'محادثة', maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall),
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
                  onPressed: _loading || thread == null ? null : () => _report(thread),
                  tooltip: 'بلاغ',
                  icon: const EbrokerIcon(Icons.flag_outlined)),
              if (thread != null && thread.otherUserId > 0) PopupMenuButton<String>(tooltip: 'خيارات المحادثة', enabled: !_blocking,
                onSelected: (action) {
                  if (!_scope.isCurrent) return;
                  if (action == 'deal' && deal != null) {
                    context.push('/broker/deals/${deal.id}');
                  } else if (action == 'record-deal' && mayRecordDeal) {
                    reportBrokerDeal(context, ref, thread.id, propertyId: thread.propertyId);
                  } else if (action == 'block') {
                    _changeBlock();
                  }
                }, itemBuilder: (_) => [
                  if (deal != null) PopupMenuItem(value: 'deal', child: Text(deal.resultActionLabel)),
                  if (mayRecordDeal) const PopupMenuItem(value: 'record-deal', child: Text('تسجيل نتيجة الصفقة')),
                  PopupMenuItem(value: 'block', child: Text(thread.blockedByMe ? 'إلغاء الحظر' : 'حظر الحساب')),
                ]),
            ]),
        body: Column(children: [
          if (thread != null) BrokerConversationTools(thread: thread, compact: true),
          if (_details != null && (_loading || _error != null)) AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
          if (!_loading && thread?.canSend == false) Padding(padding: const EdgeInsets.all(12), child: Text(thread!.blockedByMe
            ? 'هذا الحساب محظور لديك. تبقى المحادثة السابقة محفوظة.' : 'الرسائل الجديدة غير متاحة حاليًا. يبقى تاريخ المحادثة والبلاغ متاحين.')),
          if (_blocking) const LinearProgressIndicator(),
          Expanded(
            child: _loading && _details == null
                ? const AppLoadingState(label: 'جارٍ تحميل المحادثة…')
                : _error != null && _details == null
                    ? AppErrorState(message: _error!, onRetry: _load)
                    : _messageList(),
          ),
          if (_peerTyping && thread?.canSend == true)
            const Align(alignment: Alignment.centerRight, child: _TypingIndicator()),
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
                            focusNode: _composerFocus,
                            enabled: thread?.canSend == true && !_sending && !_blocking,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration:
                                const InputDecoration(hintText: 'اكتب رسالة...'),
                            onChanged: (text) => _typing.edited(text.trim().isNotEmpty),
                            onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        key: const ValueKey('broker-conversation-send'),
                        tooltip: 'إرسال الرسالة',
                        style: IconButton.styleFrom(fixedSize: const Size(46, 46),
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          shape: const CircleBorder()),
                        onPressed: _sending || _blocking || _error != null || thread?.canSend != true ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded, textDirection: TextDirection.rtl)),
                  ]))),
        ]),
      ),
    );
    return MessagingSystemNavigation(child: page);
  }

  Widget _messageList() {
    final details = _details;
    final scheme = Theme.of(context).colorScheme;
    final darkMode = scheme.brightness == Brightness.dark;
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
                          : 'بدأ الطرف الآخر اتصالاً هاتفياً',
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
        final fill = item.isMine
            ? darkMode ? scheme.primaryContainer : scheme.primary
            : scheme.surface;
        final textColor = item.isMine
            ? darkMode ? scheme.onPrimaryContainer : scheme.onPrimary
            : scheme.onSurface;
        return Align(
          alignment: item.isMine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: scheme.outlineVariant, width: .5),
                borderRadius: BorderRadius.circular(8)),
            child:
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.body, style: TextStyle(fontSize: 14, height: 1.3, color: textColor)),
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: item.isMine ? textColor : scheme.onSurfaceVariant)),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('conversation-peer-typing'),
      label: 'الطرف الآخر يكتب',
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
        child: AnimatedBuilder(animation: _motion, builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: scheme.onSurface.withValues(alpha: _motion.isAnimating &&
                    (_motion.value * 3).floor() != i ? .35 : .75))),
          ],
        )),
      ),
    );
  }
}
