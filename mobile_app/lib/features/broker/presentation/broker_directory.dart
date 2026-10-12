import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/data/auth_controller.dart';
import '../../account/domain/yemen_admin_divisions.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';
import 'broker_workspaces.dart';

class BrokerGovernorateFilter extends ConsumerWidget {
  const BrokerGovernorateFilter({this.onChanged, super.key});
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) => DropdownButtonFormField<String>(
    value: ref.watch(brokerGovernorateProvider), isExpanded: true,
    decoration: const InputDecoration(labelText: 'الدلالون حسب المحافظة'), hint: const Text('كل المحافظات'),
    items: [const DropdownMenuItem<String>(value: null, child: Text('كل المحافظات')),
      for (final name in YemenAdminDivisions.governorates) DropdownMenuItem(value: name, child: Text(name))],
    onChanged: (value) { ref.read(brokerGovernorateProvider.notifier).state = value; onChanged?.call(); },
  );
}

class BrokerDirectoryScreen extends ConsumerStatefulWidget {
  const BrokerDirectoryScreen({super.key});
  @override
  ConsumerState<BrokerDirectoryScreen> createState() => _BrokerDirectoryScreenState();
}
class _BrokerDirectoryScreenState extends ConsumerState<BrokerDirectoryScreen> {
  final List<BrokerProfile> _items = [];
  bool _loading = true, _more = false;
  int _page = 0, _request = 0;
  String? _error;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool next = false}) async {
    final request = ++_request;
    setState(() { _loading = true; _error = null; if (!next) _items.clear(); });
    try {
      final rows = await ref.read(brokerRepositoryProvider).directory(governorate: ref.read(brokerGovernorateProvider), page: next ? _page + 1 : 1);
      if (!mounted || request != _request) return;
      setState(() { _items.addAll(rows.items); _page = rows.page; _more = rows.hasMore; _loading = false; });
    } catch (error) { if (mounted && request == _request) setState(() { _loading = false; _error = friendlyApiError(error); }); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(appBar: const AppAppBar(title: 'تعرّف على الدلالين'), body: RefreshIndicator(
    onRefresh: () => _load(), child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
      BrokerGovernorateFilter(onChanged: () => _load()), const SizedBox(height: 12),
      const Text('يظهر دلالو المحافظة المختارة أولًا، ثم تتوسع النتائج. الترتيب يجمع تقييم العملاء والصفقات المؤكدة والنشاط.'),
      const SizedBox(height: 14),
      for (final profile in _items) Padding(padding: const EdgeInsets.only(bottom: 14), child: EbrokerAdvertiserCard(
        name: profile.name, identity: '${profile.typeLabel}${profile.governorate == null ? '' : ' · ${profile.governorate}'}', rating: profile.rating,
        ratingCount: profile.ratingCount, verified: profile.verified, photoUrl: profile.photoUrl,
        completedDeals: profile.completedDeals, activeListings: profile.activeListings, onTap: () => context.push('/advertisers/${profile.id}'))),
      if (_loading) const AppLoadingState(),
      if (_error != null) AppErrorState(message: _error!, onRetry: () => _load()),
      if (!_loading && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا يوجد دلالون موثقون لعرضهم الآن.')),
      if (_more && !_loading) AppButton(label: 'عرض المزيد', onPressed: () => _load(next: true)),
    ]),
  ));
}

class BrokerPublicProfileScreen extends ConsumerStatefulWidget {
  const BrokerPublicProfileScreen({required this.id, super.key});
  final int id;
  @override
  ConsumerState<BrokerPublicProfileScreen> createState() => _BrokerPublicProfileScreenState();
}
class _BrokerPublicProfileScreenState extends ConsumerState<BrokerPublicProfileScreen> {
  final List<PropertySummary> _properties = [];
  bool _loading = true, _more = false;
  int _page = 0, _request = 0;
  String? _error, _purpose;
  @override
  void initState() { super.initState(); Future.microtask(_loadProperties); }
  @override
  void didUpdateWidget(covariant BrokerPublicProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) { _properties.clear(); _page = 0; _loadProperties(); }
  }
  Future<void> _loadProperties({bool next = false}) async {
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await ref.read(propertyRepositoryProvider).advertiserListings(widget.id, page: next ? _page + 1 : 1, purpose: _purpose);
      if (!mounted || request != _request) return;
      setState(() { if (!next) _properties.clear(); _properties.addAll(rows.$1); _more = rows.$2; _page = next ? _page + 1 : 1; _loading = false; });
    } catch (e) { if (mounted && request == _request) setState(() { _loading = false; _error = friendlyApiError(e); }); }
  }
  Future<void> _editBio(BrokerProfile profile) async {
    String bio = profile.bio ?? '';
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('نبذتك العامة'),
      content: TextFormField(initialValue: bio, onChanged: (value) => bio = value, maxLength: 900, maxLines: 5, decoration: const InputDecoration(hintText: 'خبرتك والمناطق التي تعمل فيها')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), AppButton(label: 'حفظ', onPressed: () => Navigator.pop(c, true))]));
    if (ok != true) return;
    try { await ref.read(brokerRepositoryProvider).updateBio(bio); ref.invalidate(brokerProfileProvider(widget.id)); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)))); }
  }
  Future<void> _photo() async {
    final paths = await const Stage5MediaPicker().pickImages();
    if (paths.isEmpty || !mounted) return;
    try {
      await ref.read(brokerRepositoryProvider).uploadPhoto(paths.first);
      ref.invalidate(brokerProfileProvider(widget.id)); ref.invalidate(brokerDirectoryProvider);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)))); }
    finally { await const Stage5MediaPicker().clearTemporaryFiles(paths); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(appBar: const AppAppBar(title: 'الملف العام'), body: ref.watch(brokerProfileProvider(widget.id)).when(
    loading: () => const AppLoadingState(), error: (e, _) => AppErrorState(message: friendlyApiError(e), onRetry: () => ref.invalidate(brokerProfileProvider(widget.id))),
    data: (profile) => ListView(padding: const EdgeInsets.all(16), children: [
      EbrokerAdvertiserCard(name: profile.name, identity: profile.typeLabel, rating: profile.rating, ratingCount: profile.ratingCount,
        verified: profile.verified, photoUrl: profile.photoUrl, completedDeals: profile.completedDeals, activeListings: profile.activeListings, onTap: () {}),
      const SizedBox(height: 16),
      if (profile.bio?.isNotEmpty == true) Text(profile.bio!),
      if (profile.governorate != null) Text('المحافظة: ${profile.governorate}'),
      if (profile.workAreas.isNotEmpty) Text('مناطق العمل: ${profile.workAreas.join('، ')}'),
      if (profile.specializations.isNotEmpty) Text('التخصصات: ${profile.specializations.join('، ')}'),
      if (profile.joinedAt != null) Text('عضو منذ ${profile.joinedAt}'),
      if (ref.watch(authControllerProvider).asData?.value?.id == profile.id) Wrap(spacing: 8, children: [
        AppButton(label: 'تعديل النبذة', icon: Icons.edit_outlined, onPressed: () => _editBio(profile)),
        AppButton(label: 'تغيير الصورة العامة', icon: Icons.add_a_photo_outlined, onPressed: _photo),
      ]),
      const SizedBox(height: 20), Text('العقارات النشطة', style: Theme.of(context).textTheme.titleLarge),
      Wrap(spacing: 8, children: [for (final item in const [('الكل', null), ('للبيع', 'sale'), ('للإيجار', 'rent')])
        AppFilterChip(label: item.$1, selected: _purpose == item.$2, onSelected: (_) { setState(() => _purpose = item.$2); _loadProperties(); })]),
      const SizedBox(height: 8), const Text('اختر عقارًا لبدء التواصل أو طلب معاينته.'), const SizedBox(height: 12),
      for (final property in _properties) Padding(padding: const EdgeInsets.only(bottom: 12), child: EbrokerPropertyHorizontalCard(
        title: property.title, price: property.price.toStringAsFixed(0), currency: property.currency, imageUrl: property.mainImage,
        location: property.address, categoryLabel: ebrokerPropertyTypeLabel(property.type), purposeLabel: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
        onTap: () => context.push('/properties/${property.id}'))),
      if (_loading) const AppLoadingState(),
      if (_error != null) AppErrorState(message: _error!, onRetry: () => _loadProperties()),
      if (!_loading && _error == null && _properties.isEmpty) const Text('لا توجد عقارات متاحة لهذا المعلن حاليًا.'),
      if (_more && !_loading) AppButton(label: 'عرض المزيد من العقارات', onPressed: () => _loadProperties(next: true)),
    ]),
  ));
}
