import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../data/listing_account_draft_repository.dart';
import '../domain/listing_account_draft.dart';
import '../domain/property_details.dart';
import 'listing_editor_screen.dart';
import 'personal_listing_creation_gate.dart';

class ListingDraftEntryScreen extends ConsumerWidget {
  const ListingDraftEntryScreen({this.existingProperty, this.startWithAssistant = false, super.key});
  final PropertyDetails? existingProperty;
  final bool startWithAssistant;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _ListingDraftEntryBody(key: ValueKey(actor), existingProperty: existingProperty, startWithAssistant: startWithAssistant);
  }
}
class _ListingDraftEntryBody extends ConsumerStatefulWidget {
  const _ListingDraftEntryBody({this.existingProperty, required this.startWithAssistant, super.key});
  final PropertyDetails? existingProperty;
  final bool startWithAssistant;
  @override
  ConsumerState<_ListingDraftEntryBody> createState() => _ListingDraftEntryState();
}
class _ListingDraftEntryState extends ConsumerState<_ListingDraftEntryBody> {
  List<ListingAccountDraft> _drafts = [];
  List<PropertyDetails> _legacy = [];
  bool _loading = true, _all = false, _open = false, _fresh = false;
  ListingAccountDraft? _selected;
  PropertyDetails? _property;
  String? _error;
  bool _working = false;
  int _request = 0;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([ref.read(listingAccountDraftRepositoryProvider).list(),
        if (widget.existingProperty == null) ref.read(propertyRepositoryProvider).myListings()]);
      if (!mounted || request != _request) return;
      _drafts = results[0] as List<ListingAccountDraft>;
      _legacy = results.length > 1 ? (results[1] as List<PropertyDetails>).where((p) => p.status == 'draft').toList() : [];
      final id = widget.existingProperty?.id;
      if (id != null) { _property = widget.existingProperty; for (final d in _drafts) { if (d.propertyId == id) _selected = d; } _open = true; }
      else if (_drafts.isEmpty && _legacy.isEmpty) { _open = true; _fresh = false; }
    } catch (e) { if (mounted && request == _request) {
      if (!isTransientApiFailure(e)) { _drafts = []; _legacy = []; }
      _error = friendlyApiError(e);
    } }
    if (mounted && request == _request) setState(() => _loading = false);
  }
  Future<void> _resume(ListingAccountDraft draft) async {
    if (_working || _loading) return;
    setState(() { _working = true; _error = null; });
    try {
      final current = await ref.read(listingAccountDraftRepositoryProvider).get(draft.key);
      final property = current.propertyId == null ? null : await ref.read(propertyRepositoryProvider).details(current.propertyId!);
      if (mounted) setState(() { _selected = current; _property = property; _open = true; _fresh = false; });
    } catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
    finally { if (mounted) setState(() => _working = false); }
  }
  Future<void> _delete(ListingAccountDraft draft) async {
    if (_working || _loading) return;
    setState(() { _working = true; _error = null; });
    try { await ref.read(listingAccountDraftRepositoryProvider).delete(draft.key); if (mounted) await _load(); }
    catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
    finally { if (mounted) setState(() => _working = false); }
  }
  @override
  void dispose() { _request++; super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_open) {
      final editor = ListingEditorScreen(existingProperty: _property, accountDraft: _selected, startFresh: _fresh, startWithAssistant: widget.startWithAssistant);
      return _selected != null || _property != null ? editor : PersonalListingCreationGate(child: editor);
    }
    final actor = ref.watch(authControllerProvider).asData?.value;
    final canStart = actor?.isOwner != true || (_drafts.isEmpty && _legacy.isEmpty);
    return Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Align(alignment: Alignment.bottomCenter,
      child: Material(key: const ValueKey('listing-draft-choice'), color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias, borderRadius: BorderRadius.circular(22),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * .82),
          child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text('أضف عقار', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(key: const ValueKey('listing-draft-choice-close'), tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close))]),
        if (_loading && _drafts.isEmpty && _legacy.isEmpty) const AppLoadingState(label: 'جارٍ تحميل المسودات…'),
        if (_loading || _working || _error != null) AppRefreshStatus(loading: _loading || _working, error: _error, onRetry: _load),
        if (_drafts.isNotEmpty || _legacy.isNotEmpty) ...[
          Text('لديك إعلان غير مكتمل', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
          for (final draft in _all ? _drafts : _drafts.take(1)) AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text(draft.title)), PopupMenuButton<String>(tooltip: 'خيارات المسودة', enabled: !_loading && !_working, onSelected: (_) => _delete(draft),
              itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('حذف المسودة'))])]),
            const SizedBox(height: 8), LinearProgressIndicator(value: draft.progress / 100),
            const SizedBox(height: 8), Text('${draft.progress}% من البيانات الأساسية'),
            TextButton(onPressed: _loading || _working ? null : () => _resume(draft), child: const Text('متابعة الإعلان')),
          ])),
          for (final property in (_all || _drafts.isEmpty) ? _legacy.where((p) => !_drafts.any((d) => d.propertyId == p.id)) : <PropertyDetails>[])
            ListTile(title: Text(property.title), subtitle: const Text('مسودة محفوظة'),
              onTap: _working || _loading ? null : () => setState(() { _property = property; _open = true; }),
              trailing: PopupMenuButton<String>(tooltip: 'خيارات المسودة', enabled: !_working && !_loading, onSelected: (_) async {
                setState(() { _working = true; _error = null; });
                try { await ref.read(propertyRepositoryProvider).deleteListing(property.id); if (mounted) await _load(); }
                catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
                finally { if (mounted) setState(() => _working = false); }
              }, itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('حذف المسودة'))])),
          if (!_all && _drafts.length + _legacy.where((p) => !_drafts.any((d) => d.propertyId == p.id)).length > 1)
            TextButton(onPressed: () => setState(() => _all = true), child: const Text('عرض كل المسودات')),
        ],
        const SizedBox(height: 20),
        AppButton(label: 'بدء إعلان جديد', icon: Icons.add_home_outlined, expand: true,
          onPressed: !canStart || _working || _loading || _error != null ? null : () => setState(() { _fresh = true; _selected = null; _property = null; _open = true; })),
        if (!canStart) const Padding(padding: EdgeInsets.only(top: 12), child: Text('تابع عقارك الشخصي الحالي أو فعّل حساب دلال لإدارة عدة عقارات.')),
      ])))))));
  }
}

