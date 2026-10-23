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

class ListingDraftEntryScreen extends ConsumerStatefulWidget {
  const ListingDraftEntryScreen({this.existingProperty, this.startWithAssistant = false, super.key});
  final PropertyDetails? existingProperty;
  final bool startWithAssistant;
  @override
  ConsumerState<ListingDraftEntryScreen> createState() => _ListingDraftEntryState();
}
class _ListingDraftEntryState extends ConsumerState<ListingDraftEntryScreen> {
  List<ListingAccountDraft> _drafts = [];
  List<PropertyDetails> _legacy = [];
  bool _loading = true, _all = false, _open = false, _fresh = false;
  ListingAccountDraft? _selected;
  PropertyDetails? _property;
  String? _error;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([ref.read(listingAccountDraftRepositoryProvider).list(),
        if (widget.existingProperty == null) ref.read(propertyRepositoryProvider).myListings()]);
      if (!mounted) return;
      _drafts = results[0] as List<ListingAccountDraft>;
      _legacy = results.length > 1 ? (results[1] as List<PropertyDetails>).where((p) => p.status == 'draft').toList() : [];
      final id = widget.existingProperty?.id;
      if (id != null) { _property = widget.existingProperty; for (final d in _drafts) { if (d.propertyId == id) _selected = d; } _open = true; }
      else if (_drafts.isEmpty && _legacy.isEmpty) { _open = true; _fresh = false; }
    } catch (e) { if (mounted) _error = friendlyApiError(e); }
    if (mounted) setState(() => _loading = false);
  }
  Future<void> _resume(ListingAccountDraft draft) async {
    try {
      final current = await ref.read(listingAccountDraftRepositoryProvider).get(draft.key);
      final property = current.propertyId == null ? null : await ref.read(propertyRepositoryProvider).details(current.propertyId!);
      if (mounted) setState(() { _selected = current; _property = property; _open = true; _fresh = false; });
    } catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
  }
  Future<void> _delete(ListingAccountDraft draft) async {
    try { await ref.read(listingAccountDraftRepositoryProvider).delete(draft.key); if (mounted) await _load(); }
    catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
  }
  @override
  Widget build(BuildContext context) {
    if (_open) {
      final editor = ListingEditorScreen(existingProperty: _property, accountDraft: _selected, startFresh: _fresh, startWithAssistant: widget.startWithAssistant);
      return _selected != null || _property != null ? editor : PersonalListingCreationGate(child: editor);
    }
    final actor = ref.watch(authControllerProvider).asData?.value;
    final canStart = actor?.isOwner != true || (_drafts.isEmpty && _legacy.isEmpty);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: const AppAppBar(title: 'أضف عقار'),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
        if (_error != null) AppErrorState(message: _error!, onRetry: _load),
        if (_drafts.isNotEmpty || _legacy.isNotEmpty) ...[
          Text('لديك إعلان غير مكتمل', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
          for (final draft in _all ? _drafts : _drafts.take(1)) AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text(draft.title)), PopupMenuButton<String>(tooltip: 'خيارات المسودة', onSelected: (_) => _delete(draft),
              itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('حذف المسودة'))])]),
            const SizedBox(height: 8), LinearProgressIndicator(value: draft.progress / 100),
            const SizedBox(height: 8), Text('${draft.progress}% من البيانات الأساسية'),
            TextButton(onPressed: () => _resume(draft), child: const Text('متابعة الإعلان')),
          ])),
          for (final property in (_all || _drafts.isEmpty) ? _legacy.where((p) => !_drafts.any((d) => d.propertyId == p.id)) : <PropertyDetails>[])
            ListTile(title: Text(property.title), subtitle: const Text('مسودة محفوظة'),
              onTap: () => setState(() { _property = property; _open = true; }),
              trailing: PopupMenuButton<String>(tooltip: 'خيارات المسودة', onSelected: (_) async {
                try { await ref.read(propertyRepositoryProvider).deleteListing(property.id); if (mounted) await _load(); }
                catch (e) { if (mounted) setState(() => _error = friendlyApiError(e)); }
              }, itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('حذف المسودة'))])),
          if (!_all) TextButton(onPressed: () => setState(() => _all = true), child: const Text('عرض كل المسودات')),
        ],
        const SizedBox(height: 20),
        AppButton(label: 'بدء إعلان جديد', icon: Icons.add_home_outlined, expand: true,
          onPressed: !canStart ? null : () => setState(() { _fresh = true; _selected = null; _property = null; _open = true; })),
        if (!canStart) const Padding(padding: EdgeInsets.only(top: 12), child: Text('تابع عقارك الشخصي الحالي أو فعّل حساب دلال لإدارة عدة عقارات.')),
      ])));
  }
}
