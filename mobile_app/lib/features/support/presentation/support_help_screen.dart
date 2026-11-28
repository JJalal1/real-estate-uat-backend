import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/client_request_key.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';
import 'support_evidence.dart';

class SupportHelpScreen extends StatelessWidget {
  const SupportHelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppAppBar(title: 'الدعم'),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _option(context, 'الأسئلة الشائعة', Icons.help_outline,
                const _SupportFaqScreen()),
            _option(context, 'اسأل المساعد الذكي', Icons.auto_awesome_outlined,
                const SupportHelpConversationScreen(channel: 'assistant')),
            _option(
                context,
                'تحدّث مع موظف الدعم',
                Icons.support_agent_outlined,
                const SupportHelpConversationScreen(channel: 'human')),
            _option(context, 'أرسل طلب للدعم', Icons.edit_note_outlined,
                const SupportHelpConversationScreen(channel: 'ticket')),
            Card(
                child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('طلباتي'),
              onTap: () => context.push('/support?view=cases'),
            )),
          ],
        ),
      );

  Widget _option(
          BuildContext context, String title, IconData icon, Widget page) =>
      Card(
          child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => page)),
      ));
}

class _SupportFaqScreen extends ConsumerStatefulWidget {
  const _SupportFaqScreen();

  @override
  ConsumerState<_SupportFaqScreen> createState() => _SupportFaqScreenState();
}

class _SupportFaqScreenState extends ConsumerState<_SupportFaqScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(supportRepositoryProvider).help();
    _future.ignore();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppAppBar(title: 'الأسئلة الشائعة'),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppErrorState(
                  message: friendlyApiError(snapshot.error!),
                  onRetry: () => setState(_load));
            }
            if (!snapshot.hasData) {
              return const AppLoadingState(label: 'جارٍ تحميل الإجابات…');
            }
            final questions = snapshot.data!.where((item) =>
                '${item['question']} ${item['answer']}'
                    .contains(_search.trim()));
            return ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث في الأسئلة الشائعة'),
                  onChanged: (value) => setState(() => _search = value)),
              const SizedBox(height: 12),
              if (questions.isEmpty)
                const Text('ما لقينا إجابة مطابقة. تقدر تتحدث مع الدعم.'),
              for (final item in questions)
                Card(
                    child: ExpansionTile(
                        title: Text(item['question']?.toString() ?? ''),
                        children: [
                      ListTile(title: Text(item['answer']?.toString() ?? ''))
                    ])),
            ]);
          },
        ),
      );
}

class SupportHelpConversationScreen extends ConsumerStatefulWidget {
  const SupportHelpConversationScreen(
      {super.key, this.caseId, this.channel = 'ticket'});

  final int? caseId;
  final String channel;

  @override
  ConsumerState<SupportHelpConversationScreen> createState() =>
      _SupportHelpConversationScreenState();
}

class _SupportHelpConversationScreenState
    extends ConsumerState<SupportHelpConversationScreen> {
  final _composer = TextEditingController();
  final _picker = const Stage5MediaPicker();
  late final AccountRequestScope _scope;
  String _clientKey = newClientRequestKey();
  SupportCaseDetails? _case;
  String? _attachment;
  String? _error;
  Timer? _poll;
  bool _busy = false;
  bool _loading = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    if (widget.caseId != null) {
      _loading = true;
      Future<void>.microtask(_refresh);
    }
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          _case != null &&
          !_case!.summary.isClosed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refresh(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    if (!_busy && _attachment != null) {
      _picker.clearTemporaryFiles([_attachment!]).ignore();
    }
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final id = _case?.summary.id ?? widget.caseId;
    if (_busy || id == null || !_scope.isCurrent) return;
    final revision = ++_revision;
    try {
      final data = await ref.read(supportRepositoryProvider).details(id);
      if (mounted && _scope.isCurrent && revision == _revision) {
        setState(() {
          _case = data;
          _error = null;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && _scope.isCurrent && revision == _revision && !silent) {
        setState(() {
          _error = friendlyApiError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _pick() async {
    try {
      final selected = await _picker.pickSupportEvidence();
      if (selected == null) return;
      if (!mounted || !_scope.isCurrent) {
        await _picker.clearTemporaryFiles([selected]);
        return;
      }
      if (_attachment != null) {
        _picker.clearTemporaryFiles([_attachment!]).ignore();
      }
      setState(() => _attachment = selected);
    } catch (_) {
      if (mounted) _show('تعذّر إرفاق الملف. اختر صورة أو ملف PDF بحجم مناسب.');
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.length < 2) {
      _show('اكتب رسالتك أولًا.');
      return;
    }
    final file = _attachment;
    await _change(
        (repo) => _case == null
            ? repo.openInteraction(widget.channel, body, _clientKey,
                attachment: file)
            : repo.reply(_case!.summary.id, body, attachment: file),
        onSuccess: () {
      _composer.clear();
      _clientKey = newClientRequestKey();
      setState(() => _attachment = null);
      if (file != null) _picker.clearTemporaryFiles([file]).ignore();
    });
    if (!mounted && file != null) _picker.clearTemporaryFiles([file]).ignore();
  }

  Future<void> _change(
      Future<SupportCaseDetails> Function(SupportRepository) action,
      {VoidCallback? onSuccess}) async {
    if (_busy || !_scope.isCurrent) return;
    ++_revision;
    setState(() => _busy = true);
    try {
      final data = await action(ref.read(supportRepositoryProvider));
      if (!mounted || !_scope.isCurrent) return;
      setState(() {
        _case = data;
        _error = null;
      });
      onSuccess?.call();
    } catch (error) {
      if (mounted && _scope.isCurrent) _show(friendlyApiError(error));
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!_scope.isCurrent) return const SizedBox.shrink();
    final data = _case;
    final summary = data?.summary;
    final assistant = (summary?.channel ?? widget.channel) == 'assistant';
    final title = summary?.subject ??
        switch (widget.channel) {
          'assistant' => 'المساعد الذكي',
          'human' => 'محادثة مع موظف الدعم',
          _ => 'أرسل طلب للدعم',
        };
    return Scaffold(
      appBar: AppAppBar(title: title),
      body: _loading
          ? const AppLoadingState(label: 'جارٍ تحميل المحادثة…')
          : _error != null && data == null
              ? AppErrorState(message: _error!, onRetry: _refresh)
              : Column(children: [
                  if (summary != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(children: [
                          Expanded(
                              child: Text(_caseStatus(summary),
                                  style:
                                      Theme.of(context).textTheme.titleSmall)),
                          Text(summary.reference,
                              textDirection: TextDirection.ltr),
                        ])),
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                        if (data != null &&
                            data.messages.isEmpty &&
                            data.description.isNotEmpty)
                          Card(child: ListTile(title: Text(data.description))),
                        if (data != null)
                          for (final message in data.messages)
                            Align(
                              alignment: message.actorRole == 'requester'
                                  ? AlignmentDirectional.centerEnd
                                  : AlignmentDirectional.centerStart,
                              child: Card(
                                color: message.actorRole == 'requester'
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (message.actorRole == 'assistant')
                                          const Text('المساعد الذكي',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                        Text(message.body),
                                        for (final file in message.attachments)
                                          SupportAttachmentButton(
                                              caseId: data.summary.id,
                                              file: file),
                                        if (message.actionPath case final path?)
                                          TextButton(
                                              onPressed: () =>
                                                  context.push(path),
                                              child: const Text('فتح الصفحة')),
                                      ],
                                    )),
                              ),
                            ),
                      ])),
                  if (assistant && summary != null)
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => _change((repo) => repo.handoff(summary.id)),
                        child: const Text('ما انحلت المشكلة · حوّلني للدعم')),
                  if (summary?.isClosed != true)
                    SafeArea(
                        top: false,
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                if (_attachment case final file?)
                                  ListTile(
                                      dense: true,
                                      title: Text(file.split('/').last),
                                      trailing: IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: _busy
                                              ? null
                                              : () {
                                                  _picker.clearTemporaryFiles(
                                                      [file]).ignore();
                                                  setState(
                                                      () => _attachment = null);
                                                })),
                                Row(children: [
                                  IconButton(
                                      tooltip: 'إرفاق دليل',
                                      onPressed: _busy ? null : _pick,
                                      icon: const Icon(Icons.attach_file)),
                                  Expanded(
                                      child: TextField(
                                          controller: _composer,
                                          enabled: !_busy,
                                          maxLines: 4,
                                          minLines: 1,
                                          decoration: InputDecoration(
                                              hintText:
                                                  widget.channel == 'ticket' &&
                                                          summary == null
                                                      ? 'اكتب وش تحتاج'
                                                      : 'اكتب رسالتك'))),
                                  IconButton.filled(
                                      tooltip: 'إرسال',
                                      onPressed: _busy ? null : _send,
                                      icon: const Icon(Icons.send_outlined)),
                                ]),
                              ],
                            ))),
                ]),
    );
  }

  String _caseStatus(SupportCaseSummary summary) =>
      switch ((summary.status, summary.channel)) {
        ('resolved', _) => 'تم إغلاق الطلب',
        ('dismissed', _) => 'رُفض الطلب وأُغلق',
        ('waiting_requester', _) => 'بانتظار توضيحك',
        (_, 'assistant') => 'مع المساعد الذكي',
        ('open', 'human') => 'بانتظار موظف الدعم',
        ('open', _) => 'وصل طلبك للدعم',
        _ => 'قيد المعالجة',
      };
}

class SupportDecisionScreen extends ConsumerStatefulWidget {
  const SupportDecisionScreen(
      {super.key, required this.id, this.publicationHold = false});
  final int id;
  final bool publicationHold;

  @override
  ConsumerState<SupportDecisionScreen> createState() =>
      _SupportDecisionScreenState();
}

class _SupportDecisionScreenState extends ConsumerState<SupportDecisionScreen> {
  late final AccountRequestScope _scope;
  Future<Map<String, dynamic>>? _decision;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    _load();
  }

  void _load() {
    final repository = ref.read(supportRepositoryProvider);
    _decision = widget.publicationHold
        ? repository.publicationHold(widget.id)
        : repository.listingDecision(widget.id);
    _decision?.ignore();
  }

  Future<void> _review() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(supportRepositoryProvider);
      final result = await (widget.publicationHold
          ? repo.reviewPublicationHold(widget.id)
          : repo.reviewListingDecision(widget.id));
      if (mounted && _scope.isCurrent) {
        await context.push<void>('/support?case=${result.summary.id}');
      }
    } catch (error) {
      if (mounted && _scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted && _scope.isCurrent) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!_scope.isCurrent) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppAppBar(
          title: widget.publicationHold ? 'حالة النشر' : 'قرار الإعلان'),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _decision,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorState(
                message: friendlyApiError(snapshot.error!),
                onRetry: () => setState(_load));
          }
          final data = snapshot.data;
          if (data == null) {
            return const AppLoadingState(label: 'جارٍ تحميل القرار…');
          }
          final candidate = data['previous_property_id'];
          final label = switch (data['status']) {
            'returned_for_correction' => 'أُعيد الإعلان للتصحيح',
            'rejected_duplicate' => 'رُفض الإعلان بسبب التكرار',
            'under_review' => 'الإعلان قيد التحقيق',
            'submitted' => 'بانتظار مراجعة الإعلان',
            'approved' => 'اعتُمد الإعلان',
            _ => 'حالة الإعلان',
          };
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                child: ListTile(
                    title: Text(data['title']?.toString() ?? 'الإعلان'),
                    subtitle: widget.publicationHold ? null : Text(label))),
            if (data['reason'] case final String reason)
              Card(
                  child: ListTile(
                      title: const Text('سبب القرار'), subtitle: Text(reason))),
            if (candidate is int)
              ListTile(
                  title: const Text('عرض الإعلان المشابه'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/properties/$candidate')),
            if (data['can_request_review'] == true)
              AppButton(
                  label: 'مراجعة الدعم',
                  loading: _busy,
                  onPressed: _busy ? null : _review),
          ]);
        },
      ),
    );
  }
}
