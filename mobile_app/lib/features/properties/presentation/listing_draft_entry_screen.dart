import '../../../core/offline/offline_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/local/listing_recovery_store.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../data/listing_account_draft_repository.dart';
import '../domain/listing_account_draft.dart';
import '../domain/property_details.dart';
import 'listing_editor_screen.dart';
import '../domain/property_schema.dart';
import 'package:dio/dio.dart';

class ListingDraftEntryScreen extends ConsumerWidget {
  const ListingDraftEntryScreen({this.existingProperty, this.startWithAssistant = false,
    this.showSavedDrafts = false, this.resumeLatest = false, super.key});
  final PropertyDetails? existingProperty;
  final bool startWithAssistant, showSavedDrafts, resumeLatest;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _ListingDraftEntryBody(key: ValueKey((actor, epoch)), actor: actor, epoch: epoch,
        existingProperty: existingProperty, startWithAssistant: startWithAssistant,
        showSavedDrafts: showSavedDrafts, resumeLatest: resumeLatest);
  }
}
class _ListingDraftEntryBody extends ConsumerStatefulWidget {
  const _ListingDraftEntryBody({required this.actor, required this.epoch, this.existingProperty,
    required this.startWithAssistant, required this.showSavedDrafts, required this.resumeLatest, super.key});
  final int actor, epoch;
  final PropertyDetails? existingProperty;
  final bool startWithAssistant, showSavedDrafts, resumeLatest;
  @override
  ConsumerState<_ListingDraftEntryBody> createState() => _ListingDraftEntryState();
}
class _ListingDraftEntryState extends ConsumerState<_ListingDraftEntryBody> {
  List<ListingAccountDraft> _drafts = [];
  List<PropertyDetails> _legacy = [];
  List<Map<String, dynamic>> _savedLocal = [];
  Map<String, dynamic>? _local, _editorLocal;
  bool _loading = true, _open = false, _fresh = false, _working = false;
  bool _sourcesComplete = false;
  bool _confirming = false;
  late bool _showSaved = widget.showSavedDrafts;
  bool get _directResume => widget.resumeLatest && !_showSaved;
  bool _assistant = false;
  ListingAccountDraft? _selected;
  PropertyDetails? _property;
  String? _error;
  int _request = 0;
  bool get _current => mounted && Stage6SecureSessionStore.instance.sessionEpoch == widget.epoch &&
    ref.read(authControllerProvider).asData?.value?.id == widget.actor;
  ListingRecoveryStore get _store => ref.read(listingRecoveryStoreProvider);
  ListingAccountDraftRepository get _repository => ref.read(listingAccountDraftRepositoryProvider);
  ListingAccountDraft? get _automatic {
    for (final draft in _drafts) { if (draft.isRecovery) return draft; }
    return null;
  }
  bool get _localAutomatic => _local != null && isAutomaticListingRecovery(_local!) &&
    !_drafts.any((draft) => draft.key == _local!['draft_key'] && !draft.isRecovery);
  bool get _hasRecoverableWork => _local != null || _savedLocal.isNotEmpty || _drafts.isNotEmpty || _legacy.isNotEmpty;
  List<Map<String, dynamic>> get _deviceDrafts {
    final byKey = <String, Map<String, dynamic>>{};
    for (final row in _savedLocal) { if (row['draft_key'] is String) byKey[row['draft_key'] as String] = row; }
    if (_local?['draft_key'] is String) byKey[_local!['draft_key'] as String] = _local!;
    final editableIds = _legacy.map((row) => row.id).toSet();
    return byKey.values.where((row) => !_sourcesComplete ||
        row['server_property_id'] == null || editableIds.contains(row['server_property_id'])).toList(growable: false);
  }
  @override
  void initState() {
    super.initState();
    ref.listenManual(offlineConnectionProvider, (previous, next) {
      if (!_open && !_working && previous != next) Future.microtask(_load);
    });
    Future.microtask(_load);
  }
  Future<void> _load() async {
    if (!_current) return;
    final request = ++_request;
    setState(() { _loading = true; _sourcesComplete = false; _error = null; });
    try {
      final device = await Future.wait<dynamic>([
        _store.read(widget.actor, null).timeout(const Duration(seconds: 15)),
        _store.saved(widget.actor).timeout(const Duration(seconds: 15)),
      ]);
      if (!_current || request != _request) return;
      _local = device[0] as Map<String, dynamic>?; _savedLocal = device[1] as List<Map<String, dynamic>>;
      if (const [OfflineConnection.offline, OfflineConnection.unavailable]
          .contains(ref.read(offlineConnectionProvider))) {
        _drafts = []; _legacy = [];
        if (_directResume) {
          setState(() { _loading = false; _drafts = []; _legacy = []; });
          await _resumeMostRecent();
          return;
        }
        if (widget.existingProperty != null) {
          _property = widget.existingProperty;
          _open = true;
        } else if (!_showSaved && !_hasRecoverableWork) {
          _fresh = true;
          _assistant = false;
          _open = true;
        }
        if (_current) setState(() => _loading = false);
        return;
      }
      await _repository.syncRestart(widget.actor, _store);
      if (!_current || request != _request) return;
      final rows = await Future.wait<dynamic>([
        _repository.list().timeout(const Duration(seconds: 15)),
        ref.read(propertyRepositoryProvider).myListings().timeout(const Duration(seconds: 15)),
      ]);
      if (!_current || request != _request) return;
      _drafts = (rows[0] as List<ListingAccountDraft>).where((d) => !d.isRetired).toList();
      _legacy = (rows[1] as List<PropertyDetails>).where((p) =>
          p.status == 'draft' && p.canEdit && (p.createdAt == null ||
              DateTime.now().isBefore(p.createdAt!.add(const Duration(days: 7))))).toList();
      final cached = _local;
      if (cached != null && isAutomaticListingRecovery(cached) &&
          ((cached['server_revision'] as num?) ?? 0) > 0 &&
          !_drafts.any((draft) => draft.key == cached['draft_key'])) {
        // A retired automatic draft from a different device cannot be resumed.
        try {
          await _repository.get(cached['draft_key'] as String);
        } on DioException catch (error) {
          if (![404, 410].contains(error.response?.statusCode)) rethrow;
          if (!_current || request != _request) return;
          await _store.clear(widget.actor, null);
          _local = null;
        }
      }
      if (!_current || request != _request) return;
      _sourcesComplete = true;
      if (_directResume) {
        setState(() => _loading = false);
        await _resumeMostRecent();
        return;
      } else if (widget.existingProperty != null) {
        _property = widget.existingProperty;
        for (final draft in _drafts) { if (draft.propertyId == _property!.id) _selected = draft; }
        _open = true;
      } else if (!_showSaved && !_hasRecoverableWork) {
        await _protectSavedLocal();
        if (_current) { _fresh = true; _assistant = widget.startWithAssistant; _open = true; }
      }
    } catch (e) { if (_current && request == _request) {
        if (_directResume && offlineTransportFailure(e) && (_local != null || _savedLocal.isNotEmpty)) {
          setState(() { _loading = false; _drafts = []; _legacy = []; });
          await _resumeMostRecent();
          return;
        } else if (offlineTransportFailure(e) && !_showSaved && !_directResume && !_hasRecoverableWork) {
          _fresh = true;
          _assistant = false;
          _open = true;
        } else {
          _error = friendlyApiError(e); }
      }
    }
    if (_current && request == _request) setState(() => _loading = false);
  }
  Future<void> _protectSavedLocal() async {
    if (_local != null && !_localAutomatic) await _store.pinExplicitSave(widget.actor, preserveUnclassified: true);
  }
  Map<String, dynamic>? _localFor(String key) {
    if (_local?['draft_key'] == key) return _local;
    for (final row in _savedLocal) { if (row['draft_key'] == key) return row; }
    return null;
  }

  DateTime? _savedAt(Map<String, dynamic>? data) =>
      DateTime.tryParse(data?['saved_at']?.toString() ?? '');

  bool _localIsNewer(Map<String, dynamic> local, ListingAccountDraft remote) {
    final savedAt = _savedAt(local);
    final updatedAt = remote.updatedAt;
    if (savedAt != null && updatedAt != null) return !savedAt.isBefore(updatedAt);
    if (local['draft_key'] == remote.key) {
      return (local['server_revision'] as num? ?? 0) >= remote.revision;
    }
    return savedAt != null && updatedAt == null;
  }

  bool _canMergeLocal(Map<String, dynamic> local, ListingAccountDraft remote) {
    final checkpoint = local['account_checkpoint_key'];
    return (local['server_revision'] as num? ?? 0) >= remote.revision ||
        (checkpoint is String && checkpoint == remote.payload['checkpoint_key']);
  }

  Future<void> _protectOtherDeviceDraft(Object? key) async {
    if (_local != null && !_localAutomatic && _local!['draft_key'] != key) {
      await _store.pinExplicitSave(widget.actor, preserveUnclassified: true);
    }
  }

  Future<void> _resumeMostRecent() async {
    final editable = _legacy.where((item) => item.canEdit).toList(growable: false);
    final editableIds = editable.map((item) => item.id).toSet();
    final remoteDrafts = _drafts.where((draft) => draft.propertyId == null ||
        editableIds.contains(draft.propertyId)).toList(growable: false);
    final localDrafts = [if (_local != null) _local!, ..._savedLocal].where((data) =>
        data['draft_kind'] != 'retired' && (!_sourcesComplete ||
          data['server_property_id'] == null || editableIds.contains(data['server_property_id'])));
    Map<String, dynamic>? local;
    for (final data in localDrafts) {
      final date = _savedAt(data);
      final previous = _savedAt(local);
      if (local == null || (date != null && (previous == null || date.isAfter(previous)))) {
        local = data;
      }
    }
    final latestRemote = remoteDrafts.firstOrNull;
    if (local != null && (latestRemote == null || _localIsNewer(local, latestRemote))) {
      final localKey = local['draft_key'];
      final matching = remoteDrafts.where((draft) => draft.key == localKey).firstOrNull;
      if (matching == null || !_canMergeLocal(local, matching)) {
        try {
          await _protectOtherDeviceDraft(localKey);
          _resumeLocal(local);
        } catch (error) {
          if (_current) setState(() => _error = friendlyApiError(error));
        }
      } else {
        await _resume(matching, newestLocal: local);
      }
    } else if (latestRemote != null) {
      await _resume(latestRemote);
    } else if (editable.isNotEmpty) {
      _resumeProperty(editable.first);
    }
  }

  Future<void> _resume(ListingAccountDraft draft, {Map<String, dynamic>? newestLocal}) async {
    if (_working || _loading) return;
    setState(() { _working = true; _error = null; });
    try {
      final current = await _repository.get(draft.key);
      if (!_current) return;
      final property = current.propertyId == null ? null : await ref.read(propertyRepositoryProvider).details(current.propertyId!);
      if (_directResume && _current && property == null) {
        await _protectOtherDeviceDraft(current.key);
      }
      if (_current) {
        if (_directResume && property != null && (property.status != 'draft' || !property.canEdit)) {
          setState(() => _error = 'لم تعد هذه المسودة قابلة للتعديل.');
          return;
        }
        final candidate = newestLocal ?? _localFor(current.key);
        final local = candidate != null && _localIsNewer(candidate, current) &&
            _canMergeLocal(candidate, current) ? candidate : null;
        setState(() {
          _selected = current; _property = property; _editorLocal = local;
          final recovery = local ?? current.payload;
          _assistant = recovery['entry_method'] == 'assistant' && recovery['completion_only'] != true;
          _fresh = false; _open = true;
        });
      }
    } catch (e) { if (_current) setState(() => _error = friendlyApiError(e)); }
    finally { if (_current) setState(() => _working = false); }
  }
  void _resumeLocal(Map<String, dynamic> data) {
    if (_working || _loading || !_current) return;
    setState(() {
      _editorLocal = data; _selected = null; _fresh = false; _open = true;
      _assistant = data['entry_method'] == 'assistant' && data['completion_only'] != true;
    });
  }
  void _resumeProperty(PropertyDetails property) {
    if (_working || _loading || !_current) return;
    setState(() { _property = property; _assistant = false; _fresh = false; _open = true; });
  }
  Future<bool> _confirm(String title, String content) async {
    setState(() => _confirming = true);
    try {
      return await showDialog<bool>(context: context,
        builder: (context) => AlertDialog(title: Text(title), content: Text(content), actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          TextButton(key: const ValueKey('listing-confirm-discard'), onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ])) == true;
    } finally { if (_current) setState(() => _confirming = false); }
  }
  Future<void> _startNew() async {
    final offline =
        const [OfflineConnection.offline, OfflineConnection.unavailable]
            .contains(ref.read(offlineConnectionProvider));
    if (_working || _loading || (!_sourcesComplete && !offline) || !_current) return;
    setState(() { _working = true; _error = null; });
    try {
      if ((_localAutomatic || _automatic != null) &&
          !await _confirm('بدء إعلان جديد؟', 'سيُحذف التقدم التلقائي السابق. تبقى مسوداتك اليدوية محفوظة.')) {
        return;
      }
      if (!_current) return;
      final startedAt = DateTime.now().toUtc().toIso8601String();
      await _protectSavedLocal();
      if (offline) {
        await _store.rememberRestart(widget.actor, startedAt);
      } else {
        await _repository.restartAutomatic(startedAt);
        if (!_current) return;
        await _store.rememberRestart(widget.actor, startedAt);
        await _store.acknowledgeRestart(widget.actor, startedAt);
      }
      if (_current) setState(() { _fresh = true; _selected = null; _editorLocal = null; _property = null; _assistant = widget.startWithAssistant; _open = true; });
    } catch (_) { if (_current) setState(() => _error = 'لم يكتمل إلغاء التقدم المؤقت. بياناتك باقية؛ أعد المحاولة أو تابع الإعلان.'); }
    finally { if (_current) setState(() => _working = false); }
  }
  Future<void> _delete(ListingAccountDraft draft) async {
    if (_working || _loading || !_current) return;
    setState(() => _working = true);
    try {
      if (!await _confirm('حذف المسودة المحفوظة؟', 'لن تتمكن من استعادتها بعد تأكيد الحذف.') || !_current) return;
      await _repository.delete(draft.key); await _store.deleteSaved(widget.actor, draft.key);
      if (_local?['draft_key'] == draft.key) await _store.clear(widget.actor, null);
      if (_current) await _load();
    } catch (e) { if (_current) setState(() => _error = friendlyApiError(e)); }
    finally { if (_current) setState(() => _working = false); }
  }
  Future<void> _deleteLegacy(PropertyDetails property) async {
    if (_working || _loading || !_current) return;
    setState(() => _working = true);
    try {
      if (!await _confirm('حذف الإعلان المحفوظ؟', 'سيحذف ذلك مسودة الإعلان المحددة فقط.') || !_current) return;
      await ref.read(propertyRepositoryProvider).deleteListing(property.id); if (_current) await _load();
    }
    catch (e) { if (_current) setState(() => _error = friendlyApiError(e)); }
    finally { if (_current) setState(() => _working = false); }
  }
  Future<void> _deleteLocal(Map<String, dynamic> data) async {
    if (_working || _loading || !_current) return;
    setState(() => _working = true);
    try {
      if (!await _confirm('حذف المسودة المحلية؟', 'لن يحذف ذلك إعلانًا محفوظًا على الخادم.') || !_current) return;
      final key = data['draft_key'] as String;
      await _store.deleteSaved(widget.actor, key);
      if (_local?['draft_key'] == key) await _store.clear(widget.actor, null);
      if (_current) await _load();
    } catch (e) { if (_current) setState(() => _error = friendlyApiError(e)); }
    finally { if (_current) setState(() => _working = false); }
  }
  @override
  void dispose() { _request++; super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final offline =
        const [OfflineConnection.offline, OfflineConnection.unavailable]
            .contains(ref.watch(offlineConnectionProvider));
    if (_open) {
      final editor = ListingEditorScreen(existingProperty: _property, accountDraft: _selected, localRecovery: _editorLocal,
        startFresh: _fresh, startWithAssistant: _assistant, resumeSavedProgress: _selected != null || widget.resumeLatest);
      return editor;
    }
    if (_showSaved) return _saved();
    if (_directResume) return _resumeStatus(offline);
    final remote = _automatic ?? (_drafts.isEmpty ? null : _drafts.first);
    final local = _localAutomatic ? _local : _automatic != null ? null
      : _local ?? (remote == null && _savedLocal.isNotEmpty ? _savedLocal.first : null);
    final legacy = local == null && remote == null && _legacy.isNotEmpty ? _legacy.first : null;
    final title = (local?['fields'] as Map?)?['title']?.toString().trim();
    final previousAssistant = local != null ? local['entry_method'] == 'assistant' : remote?.entryMethod == 'assistant';
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(backgroundColor: Colors.transparent,
      body: Center(child: Dialog(key: const ValueKey('listing-recovery-choice'), child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_loading ? 'التحقق من التقدم المحفوظ…' : 'لديك إعلان غير مكتمل', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_loading || _working || _error != null) AppRefreshStatus(loading: _loading || _working && !_confirming, error: _error, onRetry: _load),
          if (!_loading && (local != null || remote != null || legacy != null)) ...[
            Text(title?.isNotEmpty == true ? title! : remote?.title ?? legacy?.title ?? 'إعلان محفوظ على جهازك'),
            if (remote != null && local == null) ...[const SizedBox(height: 8), LinearProgressIndicator(value: remote.progress / 100), Text('${remote.progress}% من البيانات الأساسية')],
            if (previousAssistant != widget.startWithAssistant) Text(previousAssistant ? 'ستتابع مسار الذكاء الاصطناعي السابق.' : 'ستتابع مسار التعبئة اليدوية السابق.'),
            const SizedBox(height: 16),
            AppButton(key: const ValueKey('listing-recovery-resume'), label: 'متابعة الإعلان', expand: true,
              onPressed: _working ? null : () {
                if (local != null) { _resumeLocal(local); }
                else if (remote != null) { _resume(remote); }
                else { _resumeProperty(legacy!); }
              }),
            TextButton(key: const ValueKey('listing-recovery-new'), onPressed: _working || (!_sourcesComplete && !offline)
                                            ? null : _startNew,
              child: const Text('بدء إعلان جديد')),
            if (local != null && !_localAutomatic || remote != null && !remote.isRecovery || legacy != null)
              const Text('تظل مسوداتك المحفوظة في «مسوداتي» عند بدء إعلان جديد.'),
          ],
                                  if (!_loading &&
                                      local == null &&
                                      remote == null &&
                                      legacy == null &&
                                      offline)
                                    AppButton(
                                        label: 'تجهيز إعلان على الجهاز',
                                        onPressed: _working ? null : _startNew),
          TextButton(key: const ValueKey('listing-saved-drafts'), onPressed: _working ? null : () => setState(() => _showSaved = true), child: const Text('مسوداتي')),
          TextButton(onPressed: _working ? null : () => Navigator.of(context).maybePop(), child: const Text('رجوع')),
        ])))))));
  }

  Widget _resumeStatus(bool offline) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: const AppAppBar(title: 'متابعة آخر مسودة'),
      body: _loading || _working
          ? const AppLoadingState()
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : AppEmptyState(
                  title: offline ? 'لا توجد مسودة على هذا الجهاز' : 'لا توجد مسودات محفوظة',
                  message: offline ? 'اتصل بالإنترنت للتحقق من مسودات حسابك.' : '',
                  icon: Icons.drafts_outlined,
                ),
    ),
  );

  String _location(Map<String, dynamic> payload) {
    final fields = payload['fields'] as Map? ?? const {};
    return {
      for (final key in ['governorate', 'district', 'neighborhood'])
        if ((fields[key]?.toString().trim() ?? '').isNotEmpty) fields[key].toString().trim(),
    }.join('، ');
  }

  String _localTitle(Map<String, dynamic> data) {
    final title = (data['fields'] as Map?)?['title']?.toString().trim() ?? '';
    return title.isEmpty ? 'إعلان غير مكتمل' : title;
  }

  Widget _saved() {
    final theme = Theme.of(context);
    final remote = _automatic;
    final local = _localAutomatic && (remote == null || _localIsNewer(_local!, remote)) ? _local : null;
    final progress = local != null ? DynamicPropertySchema.draftProgress(local) : remote?.progress ?? 0;
    final hasAuto = local != null || remote != null;
    final manualRows = <({String title, String place, DateTime? date, VoidCallback open, VoidCallback delete})>[
      for (final draft in _drafts.where((d) => !d.isRecovery))
        if (_localFor(draft.key) case final Map<String, dynamic> cached when
            _localIsNewer(cached, draft) && _canMergeLocal(cached, draft))
          (title: _localTitle(cached), place: _location(cached), date: _savedAt(cached),
            open: () => _resume(draft, newestLocal: cached), delete: () => _delete(draft))
        else
          (title: draft.title, place: _location(draft.payload), date: draft.updatedAt,
            open: () => _resume(draft), delete: () => _delete(draft)),
      for (final data in _deviceDrafts.where((d) => !isAutomaticListingRecovery(d) &&
          !_drafts.any((remote) => remote.key == d['draft_key'])))
        (title: _localTitle(data), place: _location(data), date: _savedAt(data),
          open: () => _resumeLocal(data), delete: () => _deleteLocal(data)),
      for (final property in _legacy.where((p) => !_drafts.any((d) => d.propertyId == p.id) &&
          !_deviceDrafts.any((d) => d['server_property_id'] == p.id)))
        (title: property.title, place: property.address ?? '', date: property.updatedAt ?? property.createdAt,
          open: () => _resumeProperty(property), delete: () => _deleteLegacy(property)),
    ]..sort((a, b) => (b.date?.millisecondsSinceEpoch ?? 0).compareTo(a.date?.millisecondsSinceEpoch ?? 0));
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: const AppAppBar(title: 'مسوداتي'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_loading || _working || _error != null)
          AppRefreshStatus(loading: _loading || _working && !_confirming, error: _error, onRetry: _load),
        if (hasAuto)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('أكمل آخر إعلان', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(local != null ? _localTitle(local) : remote!.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Text('اكتمال البيانات ${progress.clamp(0, 100)}٪'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.clamp(0, 100) / 100),
              const SizedBox(height: 12),
              AppButton(label: 'متابعة الإعلان', onPressed: _working ? null : () {
                if (local != null) { _resumeLocal(local); } else { _resume(remote!); }
              }),
            ]))),
        if (manualRows.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Text('المسودات اليدوية', style: theme.textTheme.titleLarge)),
          for (final draft in manualRows) Card(child: ListTile(
            title: Text(draft.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: draft.place.isEmpty ? null : Text(draft.place),
            onTap: _working ? null : draft.open,
            trailing: PopupMenuButton<String>(
              enabled: !_working, tooltip: 'خيارات المسودة',
              onSelected: (_) => draft.delete(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('حذف المسودة'))],
            ),
          )),
        ],
        if (!_loading && _error == null && !hasAuto && manualRows.isEmpty)
          const AppEmptyState(title: 'لا توجد مسودات محفوظة', message: '', icon: Icons.drafts_outlined),
      ])));
  }
}
