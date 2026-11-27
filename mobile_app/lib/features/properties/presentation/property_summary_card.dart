import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/property_type_icon.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../data/favorites_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_schema.dart';
import 'property_compare_actions.dart';
import 'property_favorite_status.dart';

List<AppPropertyFact> summaryPropertyFacts(PropertySummary property, {bool essentialsOnly = false}) {
  final scope = {'type': property.type, 'purpose': property.purpose};
  bool applies(String key) => DynamicPropertySchema.applies(key, scope);
  return [
    if (applies('bedrooms') && property.bedrooms != null && property.bedrooms! > 0)
      AppPropertyFact(icon: Icons.bed_outlined, label: '${arabicDigits('${property.bedrooms}')} غرف'),
    if (applies('bathrooms') && property.bathrooms != null && property.bathrooms! > 0)
      AppPropertyFact(icon: Icons.bathtub_outlined, label: '${arabicDigits('${property.bathrooms}')} حمام'),
    if (applies('area_value') && (property.areaValue ?? property.areaM2?.toDouble() ?? 0) > 0)
      AppPropertyFact(icon: Icons.square_foot_rounded, label: '${formatMoneyAmount(property.areaValue ?? property.areaM2!)} ${propertyAreaUnitLabel(property.areaUnit)}'),
    if (!essentialsOnly && applies('floor_number') && property.floorNumber?.isNotEmpty == true)
      AppPropertyFact(icon: Icons.layers_outlined, label: 'الدور ${DynamicPropertySchema.floorLabel(property.floorNumber)}'),
    if (!essentialsOnly && applies('has_parking') && property.hasParking == true)
      const AppPropertyFact(icon: Icons.local_parking_rounded, label: 'موقف'),
  ];
}

String propertyPublicationAge(DateTime publishedAt, DateTime now) {
  final elapsed = now.difference(publishedAt);
  if (elapsed.inMinutes < 1) return 'الآن';
  if (elapsed.inHours < 1) {
    return _publicationAgeLabel(elapsed.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق');
  }
  if (elapsed.inDays < 1) {
    return _publicationAgeLabel(elapsed.inHours, 'ساعة', 'ساعتين', 'ساعات');
  }
  if (elapsed.inDays < 7) {
    return _publicationAgeLabel(elapsed.inDays, 'يوم', 'يومين', 'أيام');
  }
  if (elapsed.inDays < 30) {
    return _publicationAgeLabel(elapsed.inDays ~/ 7, 'أسبوع', 'أسبوعين', 'أسابيع');
  }
  final months = (elapsed.inDays ~/ 30).clamp(1, 6).toInt();
  return _publicationAgeLabel(months, 'شهر', 'شهرين', 'أشهر');
}

String _publicationAgeLabel(int count, String singular, String dual, String plural) => switch (count) {
  1 => 'قبل $singular',
  2 => 'قبل $dual',
  _ => 'قبل ${arabicDigits('$count')} ${count <= 10 ? plural : '$singularً'}',
};

class PropertySummaryCard extends StatelessWidget {
  const PropertySummaryCard({required this.property, this.imageFirst = false,
    this.preview = false, this.compactPreview = false, this.compact = false, this.onTap, super.key});
  final PropertySummary property;
  final bool imageFirst, preview, compactPreview, compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = property, monthly = property.purpose == 'rent' && property.monthlyRent != null;
    final publishedAt = p.publishedAt;
    return EbrokerPropertyHorizontalCard(title: p.title, price: (monthly ? p.monthlyRent! : p.price).toString(), currency: p.currency,
      imageFirst: imageFirst, preview: preview, compactPreview: compactPreview,
      imageUrl: p.mainImage, imageUrls: p.imageUrls, isSpotlight: p.isSpotlight,
      propertyType: p.type, categoryLabel: ebrokerPropertyTypeLabel(p.type), location: p.address,
      purposeLabel: p.purpose == 'rent' ? 'للإيجار' : 'للبيع', priceSuffix: monthly ? 'شهريًا' : null,
      publicationAge: publishedAt == null ? null : propertyPublicationAge(publishedAt, DateTime.now()),
      facts: compact ? const [] : summaryPropertyFacts(p, essentialsOnly: preview),
      compactFacts: compact ? CompactPropertyFacts(property: p) : null,
      trailing: PropertyFavoriteAction(propertyId: p.id, enabled: p.status == 'published'),
      action: PropertyCompareAction(propertyId: p.id, enabled: p.status == 'published'),
      supportingText: [
        if (!preview && monthly && p.price != p.monthlyRent) '${p.advanceMonths != null ? 'مقدم ${arabicDigits('${p.advanceMonths}')} أشهر' : 'القيمة المعروضة'}: ${moneyLabel(p.price, p.currency)}',
      ], onTap: onTap ?? () => context.push('/properties/${p.id}', extra: p));
  }
}

List<AppPropertyFact> _compactFacts(PropertySummary property) {
  final scope = {'type': property.type, 'purpose': property.purpose};
  bool applies(String field) => DynamicPropertySchema.applies(field, scope);
  final facade = propertyFacadeLabels[property.buildingFacade];
  final floors = property.floorsCount;
  final openings = property.shopOpenings;
  return [
    AppPropertyFact(
      icon: propertyTypeIcon(property.type),
      label: ebrokerPropertyTypeLabel(property.type),
    ),
    ...summaryPropertyFacts(property),
    if (applies('floors_count') && floors != null && floors > 0)
      AppPropertyFact(
        icon: Icons.layers_outlined,
        label: '${arabicDigits('$floors')} أدوار',
      ),
    if (applies('building_facade') && facade != null)
      AppPropertyFact(
        icon: Icons.explore_outlined,
        label: facade == 'أكثر من واجهة' ? facade : 'واجهة $facade',
      ),
    if (applies('shop_openings') && openings != null && openings > 0)
      AppPropertyFact(
        icon: Icons.storefront_outlined,
        label: '${arabicDigits('$openings')} فتحات',
      ),
  ].take(6).toList(growable: false);
}

class CompactPropertyFacts extends StatelessWidget {
  const CompactPropertyFacts({required this.property, super.key});

  final PropertySummary property;

  @override
  Widget build(BuildContext context) {
    final facts = _compactFacts(property);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var start = 0; start < facts.length; start += 3)
          Padding(
            padding: EdgeInsets.only(top: start == 0 ? 0 : 3),
            child: Row(
              children: [
                for (var column = 0; column < 3; column++)
                  Expanded(
                    child: start + column >= facts.length
                        ? const SizedBox.shrink()
                        : Tooltip(
                            message: facts[start + column].label,
                            excludeFromSemantics: true,
                            child: Row(
                              children: [
                                Icon(facts[start + column].icon,
                                    size: 13, color: color),
                                const SizedBox(width: 3),
                                Flexible(
                                    child: Text(
                                  facts[start + column].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: color,
                                    fontSize: 10,
                                  ),
                                )),
                                const SizedBox(width: 3),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class PropertyFavoriteAction extends ConsumerStatefulWidget {
  const PropertyFavoriteAction({required this.propertyId, this.enabled = true, super.key});
  final int propertyId;
  final bool enabled;
  @override
  ConsumerState<PropertyFavoriteAction> createState() => _PropertyFavoriteState();
}
class _PropertyFavoriteState extends ConsumerState<PropertyFavoriteAction> {
  bool _busy = false;
  Future<void> _toggle(bool selected) async {
    if (_busy) return;
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null || !user.isActive) {
      ref.read(pendingFavoriteAfterAuthProvider.notifier).state = widget.propertyId;
      setAuthReturnLocation(ref, '/properties/${widget.propertyId}');
      await context.push(user == null ? '/auth' : '/verify-phone');
      if (mounted && ref.read(authControllerProvider).asData?.value == null) {
        if (ref.read(pendingFavoriteAfterAuthProvider) == widget.propertyId) ref.read(pendingFavoriteAfterAuthProvider.notifier).state = null;
        takeAuthReturnLocation(ref);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(favoritesRepositoryProvider);
      if (selected) { await repo.remove(widget.propertyId); } else { await repo.add(widget.propertyId); }
      if (!mounted) return;
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(selected ? 'تمت إزالة العقار من المفضلة.' : 'تم حفظ العقار في المفضلة.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final status = PropertyFavoriteStatus.fromAsync(
      user?.isActive == true ? ref.watch(favoritePropertyIdsProvider) : null, widget.propertyId);
    return IconButton(key: ValueKey('favorite-property-${widget.propertyId}'), tooltip: status.tooltip,
      onPressed: _busy || !widget.enabled || status.loading ? null : status.failed
          ? () => ref.invalidate(favoritePropertyIdsProvider) : () => _toggle(status.selected),
      isSelected: status.selected,
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.secondary,
        minimumSize: const Size(48, 48), padding: const EdgeInsets.all(8), shape: const CircleBorder()),
      icon: Container(width: 32, height: 32, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), shape: BoxShape.circle),
        child: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(status.icon, size: 19, color: status.iconColor)));
  }
}
