import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_home/favorite_visual.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../data/favorites_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_schema.dart';
import 'property_compare_actions.dart';

List<AppPropertyFact> summaryPropertyFacts(PropertySummary property) {
  final scope = {'type': property.type, 'purpose': property.purpose};
  bool applies(String key) => DynamicPropertySchema.applies(key, scope);
  return [
    if (applies('bedrooms') && property.bedrooms != null && property.bedrooms! > 0)
      AppPropertyFact(icon: Icons.bed_outlined, label: '${arabicDigits('${property.bedrooms}')} غرف'),
    if (applies('bathrooms') && property.bathrooms != null && property.bathrooms! > 0)
      AppPropertyFact(icon: Icons.bathtub_outlined, label: '${arabicDigits('${property.bathrooms}')} حمام'),
    if (applies('area_value') && (property.areaValue ?? property.areaM2?.toDouble() ?? 0) > 0)
      AppPropertyFact(icon: Icons.square_foot_rounded, label: '${formatMoneyAmount(property.areaValue ?? property.areaM2!)} ${propertyAreaUnitLabel(property.areaUnit)}'),
    if (applies('floor_number') && property.floorNumber?.isNotEmpty == true)
      AppPropertyFact(icon: Icons.layers_outlined, label: 'الدور ${DynamicPropertySchema.floorLabel(property.floorNumber)}'),
    if (applies('has_parking') && property.hasParking == true) const AppPropertyFact(icon: Icons.local_parking_rounded, label: 'موقف'),
  ];
}

class PropertySummaryCard extends StatelessWidget {
  const PropertySummaryCard({required this.property, this.imageFirst = false, this.onTap, super.key});
  final PropertySummary property;
  final bool imageFirst;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = property, monthly = property.purpose == 'rent' && property.monthlyRent != null;
    return EbrokerPropertyHorizontalCard(title: p.title, price: (monthly ? p.monthlyRent! : p.price).toString(), currency: p.currency,
      imageFirst: imageFirst, imageUrl: p.mainImage, imageUrls: p.imageUrls, isSpotlight: p.isSpotlight,
      propertyType: p.type, categoryLabel: ebrokerPropertyTypeLabel(p.type), location: p.address,
      purposeLabel: p.purpose == 'rent' ? 'للإيجار' : 'للبيع', priceSuffix: monthly ? 'شهريًا' : null,
      facts: summaryPropertyFacts(p), trailing: PropertyFavoriteAction(propertyId: p.id, enabled: p.status == 'published'),
      action: PropertyCompareAction(propertyId: p.id, enabled: p.status == 'published'), supportingText: [
        if (monthly && p.price != p.monthlyRent) '${p.advanceMonths != null ? 'مقدم ${arabicDigits('${p.advanceMonths}')} أشهر' : 'القيمة المعروضة'}: ${moneyLabel(p.price, p.currency)}',
      ], onTap: onTap ?? () => context.push('/properties/${p.id}', extra: p));
  }
}

class PropertyFavoriteAction extends ConsumerStatefulWidget {
  const PropertyFavoriteAction({required this.propertyId, this.enabled = true, this.sourceStyle = false, super.key});
  final int propertyId;
  final bool enabled;
  final bool sourceStyle;
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
    final selected = user?.isActive == true && (ref.watch(favoritePropertyIdsProvider).asData?.value.contains(widget.propertyId) ?? false);
    if (widget.sourceStyle) {
      return EbrokerHomeFavoriteVisual(key: ValueKey('favorite-property-${widget.propertyId}'),
        selected: selected, busy: _busy, onPressed: _busy || !widget.enabled ? null : () => _toggle(selected));
    }
    return IconButton(key: ValueKey('favorite-property-${widget.propertyId}'), tooltip: selected ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
      onPressed: _busy || !widget.enabled ? null : () => _toggle(selected),
      isSelected: selected,
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.secondary,
        minimumSize: const Size(48, 48), padding: const EdgeInsets.all(8), shape: const CircleBorder()),
      icon: Container(width: 32, height: 32, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), shape: BoxShape.circle),
        child: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(selected ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 19)));
  }
}
