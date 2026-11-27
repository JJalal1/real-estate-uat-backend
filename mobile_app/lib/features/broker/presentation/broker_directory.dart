import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';
import 'broker_workspaces.dart';
import 'broker_contact_button.dart';
import 'broker_public_profile.dart';

class BrokerGovernorateFilter extends ConsumerWidget {
  const BrokerGovernorateFilter({this.onChanged, super.key});
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) => DropdownButtonFormField<String>(
    value: ref.watch(brokerGovernorateProvider), isExpanded: true,
    decoration: const InputDecoration(labelText: 'المحافظة'), hint: const Text('كل المحافظات'),
    items: [const DropdownMenuItem<String>(value: null, child: Text('كل المحافظات')),
      for (final name in brokerGovernorates) DropdownMenuItem(value: name, child: Text(name))],
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
  String? _error, _accountType;
  double? _minRating;
  final _search = TextEditingController();
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool next = false}) async {
    final request = ++_request;
    setState(() { _loading = true; _error = null; if (!next) _items.clear(); });
    try {
      final rows = await ref.read(brokerRepositoryProvider).directory(governorate: ref.read(brokerGovernorateProvider), page: next ? _page + 1 : 1, regionOnly: true,
        search: _search.text, accountType: _accountType, minRating: _minRating);
      if (!mounted || request != _request) return;
      setState(() { _items.addAll(rows.items); _page = rows.page; _more = rows.hasMore; _loading = false; });
    } catch (error) { if (mounted && request == _request) setState(() { _loading = false; _error = friendlyApiError(error); }); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(appBar: const AppAppBar(title: 'تعرّف على الدلالين'), body: RefreshIndicator(
    onRefresh: () => _load(), child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
      const Text('اسم الدلال أو المكتب'), const SizedBox(height: 8),
      TextField(key: const ValueKey('broker-directory-search'), controller: _search, textInputAction: TextInputAction.search, maxLength: 120,
        decoration: const InputDecoration(hintText: 'ابحث بالاسم', prefixIcon: Icon(Icons.search), counterText: ''), onSubmitted: (_) => _load()),
      const SizedBox(height: 12), BrokerGovernorateFilter(onChanged: () => _load()), const SizedBox(height: 12),
      Wrap(spacing: 8, children: [for (final item in const [('الكل', null), ('دلالون', 'broker'), ('مكاتب', 'office')])
        FilterChip(label: Text(item.$1), selected: _accountType == item.$2, onSelected: (_) { setState(() => _accountType = item.$2); _load(); })]),
      const SizedBox(height: 12),
      DropdownButtonFormField<double>(key: const ValueKey('broker-directory-rating'), value: _minRating, isExpanded: true,
          decoration: const InputDecoration(labelText: 'تقييم العملاء المؤكد'), items: const [DropdownMenuItem(value: null, child: Text('مع التقييم أو بدونه')),
            DropdownMenuItem(value: 4, child: Text('4 نجوم فأكثر')), DropdownMenuItem(value: 3, child: Text('3 نجوم فأكثر'))],
          onChanged: (value) { setState(() => _minRating = value); _load(); }),
      const SizedBox(height: 12),
      Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('broker-directory-apply'), onPressed: () => _load(), icon: const Icon(Icons.search), label: const Text('بحث في الدليل'))),
      const SizedBox(height: 14),
      for (final profile in _items) Padding(padding: const EdgeInsets.only(bottom: 14), child: EbrokerAdvertiserCard(
        name: profile.name, identity: [
          if (profile.marketplaceRoleLabel case final role?) role,
          if (profile.governorate case final governorate?) governorate,
        ].join(' · '), rating: profile.rating,
        ratingCount: profile.ratingCount, verified: profile.marketplaceVerified, photoUrl: profile.photoUrl,
        completedDeals: profile.completedDeals, activeListings: profile.activeListings, action: const ['broker','office'].contains(profile.type) ? BrokerContactButton(brokerId:profile.id) : null, onTap: () async { await context.push('/advertisers/${profile.id}'); if (mounted) _load(); })),
      if (_loading) const AppLoadingState(),
      if (_error != null) AppErrorState(message: _error!, onRetry: () => _load()),
      if (!_loading && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد نتائج مطابقة.')),
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
  @override
  Widget build(BuildContext context) => BrokerScaffold(appBar: const AppAppBar(title: 'الملف العام'), body: ref.watch(brokerProfileProvider(widget.id)).when(
    loading: () => const AppLoadingState(), error: (e, _) => AppErrorState(message: friendlyApiError(e), onRetry: () => ref.invalidate(brokerProfileProvider(widget.id))),
    data: (profile) => ListView(padding: const EdgeInsets.all(16), children: [
      BrokerPublicProfileSummary(
        profile: profile,
        contact: const ['broker', 'office'].contains(profile.type)
            ? BrokerContactButton(brokerId: profile.id)
            : null,
      ),
      BrokerPublicProfileActions(profile: profile),
      const SizedBox(height: 20), Text('العقارات النشطة', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [for (final item in const [('الكل', null), ('للبيع', 'sale'), ('للإيجار', 'rent')])
        AppFilterChip(label: item.$1, selected: _purpose == item.$2, onSelected: (_) { setState(() => _purpose = item.$2); _loadProperties(); })]),
      const SizedBox(height: 8), const Text('اختر عقارًا للتواصل ومناقشة المعاينة داخل المحادثة.'), const SizedBox(height: 12),
      for (final property in _properties) Padding(padding: const EdgeInsets.only(bottom: 12), child: EbrokerPropertyHorizontalCard(
        title: property.title, price: property.price.toStringAsFixed(0), currency: property.currency, imageUrl: property.mainImage, imageUrls: property.imageUrls, isSpotlight: property.isSpotlight,
        location: property.address, categoryLabel: ebrokerPropertyTypeLabel(property.type), purposeLabel: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
        onTap: () => context.push('/properties/${property.id}'))),
      if (_loading) const AppLoadingState(),
      if (_error != null) AppErrorState(message: _error!, onRetry: () => _loadProperties()),
      if (!_loading && _error == null && _properties.isEmpty) const Text('لا توجد عقارات متاحة لهذا المعلن حاليًا.'),
      if (_more && !_loading) AppButton(label: 'عرض المزيد من العقارات', onPressed: () => _loadProperties(next: true)),
    ]),
  ));
}
