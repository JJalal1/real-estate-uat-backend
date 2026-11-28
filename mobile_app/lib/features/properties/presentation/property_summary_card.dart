import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_card_actions.dart';
import '../../../core/widgets/property_card_gallery.dart';
import '../../../core/local/stage6_secure_session_store.dart';
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
import 'property_compare_screen.dart';
import 'property_favorite_status.dart';

List<AppPropertyFact> summaryPropertyFacts(PropertySummary property, {
  bool essentialsOnly = false,
  bool abbreviateArea = false,
}) {
  final scope = {'type': property.type, 'purpose': property.purpose};
  bool applies(String key) => DynamicPropertySchema.applies(key, scope);
  final areaUnit = propertyAreaUnitLabel(property.areaUnit);
  return [
    if (applies('bedrooms') && property.bedrooms != null && property.bedrooms! > 0)
      AppPropertyFact(icon: Icons.bed_outlined, label: '${arabicDigits('${property.bedrooms}')} غرف'),
    if (applies('bathrooms') && property.bathrooms != null && property.bathrooms! > 0)
      AppPropertyFact(icon: Icons.bathtub_outlined, label: '${arabicDigits('${property.bathrooms}')} حمام'),
    if (applies('area_value') && (property.areaValue ?? property.areaM2?.toDouble() ?? 0) > 0)
      AppPropertyFact(icon: Icons.square_foot_rounded, label: '${formatMoneyAmount(property.areaValue ?? property.areaM2!)} ${abbreviateArea && areaUnit == 'متر مربع' ? 'م²' : areaUnit}'),
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

enum HomePropertySection { latest, nearby, recent }

class PropertySummaryCard extends StatelessWidget {
  const PropertySummaryCard({required this.property, this.imageFirst = false,
    this.preview = false, this.compactPreview = false, this.compact = false, this.searchResult = false, this.knownFavorite = false,
    this.homeSection, this.nearbyDistance, this.onTap, super.key});
  final PropertySummary property;
  final bool imageFirst, preview, compactPreview, compact, searchResult, knownFavorite;
  final HomePropertySection? homeSection;
  final String? nearbyDistance;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = property, monthly = property.purpose == 'rent' && property.monthlyRent != null;
    final publishedAt = p.publishedAt;
    final age = publishedAt == null ? null : propertyPublicationAge(publishedAt, DateTime.now());
    final homeRail = homeSection != null;
    final location = homeRail
        ? p.address?.split(RegExp(r'[,،]')).map((part) => part.trim())
            .where((part) => part.isNotEmpty).take(2).join('، ')
        : p.address;
    final locationDetail = switch (homeSection) {
      HomePropertySection.latest => age,
      HomePropertySection.nearby => nearbyDistance,
      _ => null,
    };
    final supportingText = [
      if (!preview && monthly && p.price != p.monthlyRent)
        '${p.advanceMonths != null ? 'مقدم ${arabicDigits('${p.advanceMonths}')} أشهر' : 'القيمة المعروضة'}: ${moneyLabel(p.price, p.currency)}',
    ];
    final VoidCallback open = onTap ?? () => context.push('/properties/${p.id}', extra: p);
    if (compact || searchResult) {
      final state = listingStatus(p.status, p.availabilityStatus, published: p.status == 'published');
      final details = [if (age != null) age, ...supportingText];
      return ListingPropertyCard(
        property: p,
        price: (monthly ? p.monthlyRent! : p.price).toString(),
        priceSuffix: monthly ? 'شهريًا' : null,
        onTap: open,
        details: searchResult ? details : const [],
        badge: searchResult
            ? PropertyCompareAction(propertyId: p.id, enabled: p.status == 'published', compact: true)
            : state == null ? null : AppStatusBadge(label: state.$1, tone: state.$2),
        actionsMenu: PropertyFavoriteAction(
          propertyId: p.id,
          enabled: p.status == 'published' && (searchResult || p.availabilityStatus == 'available'),
          includeComparison: !searchResult,
          knownFavorite: knownFavorite,
          menuDetails: details,
        ),
      );
    }
    return EbrokerPropertyHorizontalCard(title: p.title, price: (monthly ? p.monthlyRent! : p.price).toString(), currency: p.currency,
      imageFirst: imageFirst, preview: preview, compactPreview: compactPreview, homeRail: homeRail,
      imageUrl: p.mainImage, imageUrls: p.imageUrls, isSpotlight: p.isSpotlight,
      propertyType: p.type, categoryLabel: ebrokerPropertyTypeLabel(p.type), location: location,
      locationDetail: locationDetail,
      purposeLabel: p.purpose == 'rent' ? 'للإيجار' : 'للبيع', priceSuffix: monthly ? 'شهريًا' : null,
      publicationAge: homeRail ? null : age,
      facts: summaryPropertyFacts(p, essentialsOnly: preview, abbreviateArea: homeRail),
      trailing: PropertyFavoriteAction(propertyId: p.id, enabled: p.status == 'published'),
      action: PropertyCompareAction(propertyId: p.id, enabled: p.status == 'published', compact: homeRail),
      supportingText: supportingText, onTap: open);
  }
}

(String, AppStatusTone)? listingStatus(String status, String availability, {required bool published}) =>
    switch (availability) {
      'sold' => ('تم البيع', AppStatusTone.neutral),
      'rented' => ('تم التأجير', AppStatusTone.neutral),
      'paused' => ('متوقف مؤقتًا', AppStatusTone.neutral),
      'confirmation_paused' => ('يحتاج تحديثًا', AppStatusTone.warning),
      _ when published => ('منشور', AppStatusTone.success),
      _ when status == 'archived' => ('مؤرشف', AppStatusTone.neutral),
      _ when status == 'unavailable' => ('غير متاح', AppStatusTone.neutral),
      _ => null,
    };

/// Shared size, media and text layout of a listing in My Listings and its consumer lists.
class ListingPropertyCard extends StatelessWidget {
  const ListingPropertyCard({
    required this.property,
    required this.price,
    required this.onTap,
    this.priceSuffix,
    this.actionsMenu,
    this.details = const [],
    this.badge,
    this.footer,
    this.authenticatedImages = false,
    super.key,
  });

  final PropertySummary property;
  final String price;
  final String? priceSuffix;
  final VoidCallback onTap;
  final Widget? actionsMenu, badge, footer;
  final List<String> details;
  final bool authenticatedImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = property.address?.trim();
    final isRent = property.purpose == 'rent';

    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * .28)
                      .clamp(70.0, 110.0)
                      .toDouble(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PropertyCardGallery(
                      key: const ValueKey('my-listing-photo'),
                      height: 122,
                      imageUrl: property.mainImage,
                      imageUrls: property.imageUrls,
                      authenticatedImages: authenticatedImages,
                      isSpotlight: property.isSpotlight,
                      propertyType: property.type,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: AppPropertyPrice(
                            price: price,
                            suffix: priceSuffix,
                            currency: property.currency,
                            compact: true,
                          )),
                          const SizedBox(width: 4),
                          EbrokerPurposeLabel(isRent ? 'للإيجار' : 'للبيع'),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                            property.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.propertyName,
                          )),
                          if (actionsMenu != null) actionsMenu!,
                        ],
                      ),
                      if (address != null && address.isNotEmpty)
                        Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.propertySecondary.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      for (final line in details)
                        Text(line, style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 5),
                      CompactPropertyFacts(
                        key: const ValueKey('my-listing-facts'),
                        property: property,
                      ),
                      if (badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: badge!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class ListingCardActionsMenu extends StatelessWidget {
  const ListingCardActionsMenu({required this.actions, this.details = const [], super.key});

  final List<EbrokerCardAction> actions;
  final List<String> details;

  @override
  Widget build(BuildContext context) => PopupMenuButton<EbrokerCardAction>(
        tooltip: 'خيارات البطاقة',
        icon: const EbrokerIcon(Icons.more_vert, size: 18),
        padding: EdgeInsets.zero,
        onSelected: (action) => action.onPressed?.call(),
        itemBuilder: (_) => [
          for (final action in actions)
            PopupMenuItem<EbrokerCardAction>(
              key: action.key,
              value: action,
              enabled: action.onPressed != null,
              child: Row(
                children: [
                  EbrokerIcon(action.icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(action.label)),
                ],
              ),
            ),
          if (details.isNotEmpty)
            PopupMenuItem<EbrokerCardAction>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final detail in details) Text(detail)],
              ),
            ),
        ],
      );
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
  const PropertyFavoriteAction({required this.propertyId, this.enabled = true,
    this.includeComparison = false, this.knownFavorite = false, this.menuDetails = const [], super.key});
  final int propertyId;
  final bool enabled, includeComparison, knownFavorite;
  final List<String> menuDetails;
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
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    bool sameActor() => Stage6SecureSessionStore.instance.sessionEpoch == epoch &&
        ref.read(authControllerProvider).asData?.value?.id == user.id;
    setState(() => _busy = true);
    try {
      final repo = ref.read(favoritesRepositoryProvider);
      if (selected) { await repo.remove(widget.propertyId); } else { await repo.add(widget.propertyId); }
      if (!mounted || !sameActor()) return;
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(selected ? 'تمت إزالة العقار من المفضلة.' : 'تم حفظ العقار في المفضلة.')));
    } catch (e) {
      if (mounted && sameActor()) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final status = widget.knownFavorite
        ? const PropertyFavoriteStatus.ready(true)
        : PropertyFavoriteStatus.fromAsync(
            user?.isActive == true ? ref.watch(favoritePropertyIdsProvider) : null, widget.propertyId);
    final VoidCallback? favorite = _busy || !widget.enabled || status.loading ? null : status.failed
        ? () => ref.invalidate(favoritePropertyIdsProvider) : () => _toggle(status.selected);
    if (widget.includeComparison) {
      final selection = ref.watch(propertyCompareSelectionProvider);
      final compared = selection.contains(widget.propertyId);
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      final actor = user?.id;
      return ListingCardActionsMenu(details: widget.menuDetails, actions: [
        EbrokerCardAction(status.tooltip, favorite == null ? null : () {
          if (mounted && epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
              actor == ref.read(authControllerProvider).asData?.value?.id) {
            favorite();
          }
        }, icon: status.icon,
            key: ValueKey('favorite-property-${widget.propertyId}')),
        EbrokerCardAction(compared ? 'مضاف للمقارنة' : 'أضف للمقارنة',
            widget.enabled ? () => togglePropertyComparison(context, ref, widget.propertyId) : null,
            icon: compared ? Icons.check : Icons.compare_arrows,
            key: ValueKey('compare-property-${widget.propertyId}')),
        if (selection.length == 2)
          EbrokerCardAction('قارن العقارين', () {
            Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => PropertyCompareScreen(propertyIds: selection.toList(growable: false)),
            ));
          }, icon: Icons.compare_arrows),
      ]);
    }
    return IconButton(key: ValueKey('favorite-property-${widget.propertyId}'), tooltip: status.tooltip,
      onPressed: favorite,
      isSelected: status.selected,
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.secondary,
        minimumSize: const Size(48, 48), padding: const EdgeInsets.all(8), shape: const CircleBorder()),
      icon: Container(width: 32, height: 32, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), shape: BoxShape.circle),
        child: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(status.icon, size: 19, color: status.iconColor)));
  }
}
