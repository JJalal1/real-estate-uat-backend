import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/client_request_key.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../data/support_workspace_repository.dart';
import '../domain/support_workspace_models.dart';

class SupportMessagesScreen extends ConsumerStatefulWidget {
  const SupportMessagesScreen(
      {super.key,
      this.manager = false,
      this.executive = false,
      this.actingAsAgent = false});

  final bool manager;
  final bool executive;
  final bool actingAsAgent;

  @override
  ConsumerState<SupportMessagesScreen> createState() =>
      _SupportMessagesScreenState();
}

class _SupportMessagesScreenState extends ConsumerState<SupportMessagesScreen> {
  late final AccountRequestScope _scope;
  List<SupportStaffThread> _internal = const [];
  List<SupportTaskItem> _cases = const [];
  int _page = 0;
  int _revision = 0;
  bool _more = false;
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    Future<void>.microtask(_refresh);
  }

  Future<void> _refresh() => _load(1);

  Future<void> _load(int page) async {
    if (!_scope.isCurrent) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(supportWorkspaceRepositoryProvider);
      final internal = page == 1 ? await repo.staffThreads() : _internal;
      final results = widget.executive
          ? null
          : await repo.messages(
              page: page, actingAsAgent: widget.actingAsAgent);
      if (!mounted || !_scope.isCurrent || revision != _revision) return;
      setState(() {
        _internal = internal;
        _cases = <int, SupportTaskItem>{
          if (page > 1)
            for (final task in _cases) task.id: task,
          for (final task in results?.items ?? const <SupportTaskItem>[])
            task.id: task,
        }.values.toList();
        _page = page;
        _more = results?.hasMore ?? false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_scope.isCurrent || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _openExecutive() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final thread =
          await ref.read(supportWorkspaceRepositoryProvider).openStaffThread();
      if (mounted && _scope.isCurrent) {
        await context.push<void>('/support/internal/${thread.id}');
        if (mounted) await _refresh();
      }
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!_scope.isCurrent) return const SizedBox.shrink();
    return Scaffold(
      appBar:
          AppAppBar(title: widget.executive ? 'مراسلات فرق الدعم' : 'الرسائل'),
      body: _loading && _internal.isEmpty && _cases.isEmpty
          ? const AppLoadingState(label: 'جارٍ تحميل المحادثات…')
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (widget.manager)
                    Card(
                        child: ListTile(
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: const Text('مراسلة المدير العام'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: _opening ? null : _openExecutive)),
                  if (_error case final error?)
                    ListTile(
                        title: Text(error),
                        trailing: IconButton(
                            tooltip: 'إعادة المحاولة',
                            icon: const Icon(Icons.refresh),
                            onPressed: _refresh)),
                  for (final thread in _internal)
                    Card(
                        child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(thread.name),
                      subtitle: Text(
                          [
                            if (thread.team != null) thread.team!,
                            if (thread.preview != null) thread.preview!
                          ].join('\n'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () async {
                        await context
                            .push<void>('/support/internal/${thread.id}');
                        if (mounted) await _refresh();
                      },
                    )),
                  for (final task in _cases)
                    Card(
                        child: ListTile(
                      leading: const Icon(Icons.support_agent_outlined),
                      title: Text(task.requesterName ?? task.subject),
                      subtitle: Text(
                          [
                            task.subject,
                            if (task.lastMessagePreview != null)
                              task.lastMessagePreview!
                          ].join('\n'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      trailing: task.status == 'escalated'
                          ? const Text('مصعّد')
                          : const Icon(Icons.chevron_left),
                      onTap: () async {
                        await context.push<void>(
                            '/support/workspace/tasks/${task.id}${widget.manager ? '?manager=1' : ''}');
                        if (mounted) await _refresh();
                      },
                    )),
                  if (!_loading &&
                      _error == null &&
                      _internal.isEmpty &&
                      _cases.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد محادثات مفتوحة.')),
                  if (_more)
                    TextButton(
                        onPressed: _loading ? null : () => _load(_page + 1),
                        child: const Text('المزيد')),
                ],
              )),
    );
  }
}

class SupportStaffChatScreen extends ConsumerStatefulWidget {
  const SupportStaffChatScreen(
      {super.key, required this.threadId, this.linkedTaskId});
  final int threadId;
  final int? linkedTaskId;

  @override
  ConsumerState<SupportStaffChatScreen> createState() =>
      _SupportStaffChatScreenState();
}

class _SupportStaffChatScreenState
    extends ConsumerState<SupportStaffChatScreen> {
  final _composer = TextEditingController();
  late final AccountRequestScope _scope;
  String _clientKey = newClientRequestKey();
  SupportStaffThread? _thread;
  List<SupportStaffMessage> _older = const [];
  int? _linkedTask;
  bool _loading = false, _sending = false, _more = true;
  Timer? _poll;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    _linkedTask = widget.linkedTaskId;
    Future<void>.microtask(_refresh);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refresh(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false, bool older = false}) async {
    if (_sending || _loading || !_scope.isCurrent) return;
    _loading = true;
    try {
      final before = older
          ? (_older.isEmpty
              ? _thread?.messages.firstOrNull?.id
              : _older.first.id)
          : null;
      final thread = await ref
          .read(supportWorkspaceRepositoryProvider)
          .staffThread(widget.threadId, before: before);
      if (!mounted || !_scope.isCurrent) return;
      setState(() {
        if (older) {
          _older = [...thread.messages, ..._older];
          _more = thread.messages.length >= 50;
        } else {
          _thread = thread;
        }
        _error = null;
      });
    } catch (error) {
      if (!mounted || !_scope.isCurrent) return;
      if (!isTransientApiFailure(error)) {
        setState(() {
          _thread = null;
          _older = const [];
          _error = friendlyApiError(error);
        });
      } else if (!silent) {
        setState(() => _error = friendlyApiError(error));
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    if (_sending ||
        _loading ||
        !_scope.isCurrent ||
        _composer.text.trim().isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      final data = await ref
          .read(supportWorkspaceRepositoryProvider)
          .sendStaffMessage(widget.threadId, _composer.text.trim(), _clientKey,
              taskId: _linkedTask);
      if (!mounted || !_scope.isCurrent) return;
      setState(() {
        _thread = data;
        _linkedTask = null;
        _clientKey = newClientRequestKey();
      });
      _composer.clear();
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!_scope.isCurrent) return const SizedBox.shrink();
    final thread = _thread;
    return Scaffold(
      appBar: AppAppBar(title: thread?.name ?? 'محادثة داخلية'),
      body: thread == null
          ? _error != null
              ? AppErrorState(message: _error!, onRetry: _refresh)
              : const AppLoadingState(label: 'جارٍ تحميل المحادثة…')
          : Column(children: [
              Expanded(
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                if (_more && thread.messages.length >= 50)
                  TextButton(
                      onPressed: () => _refresh(older: true),
                      child: const Text('رسائل أقدم')),
                for (final message in {
                  ...{for (final m in _older) m.id: m},
                  for (final m in thread.messages) m.id: m
                }.values)
                  Align(
                      alignment: message.mine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Card(
                          color: message.mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(message.body),
                                  if (message.taskId case final task?)
                                    TextButton.icon(
                                        icon: const Icon(
                                            Icons.assignment_outlined),
                                        onPressed: () => context.push(
                                            '/support/workspace/tasks/$task?manager=1'),
                                        label: const Text('فتح المهمة')),
                                ],
                              )))),
              ])),
              if (_linkedTask case final task?)
                ListTile(
                    dense: true,
                    title: Text('مهمة #$task'),
                    trailing: IconButton(
                        onPressed: _sending
                            ? null
                            : () => setState(() => _linkedTask = null),
                        icon: const Icon(Icons.close))),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: _composer,
                                enabled: !_sending,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                    hintText: 'اكتب رسالة'))),
                        IconButton.filled(
                            onPressed: _sending ? null : _send,
                            tooltip: 'إرسال',
                            icon: const Icon(Icons.send_outlined)),
                      ]))),
            ]),
    );
  }
}
