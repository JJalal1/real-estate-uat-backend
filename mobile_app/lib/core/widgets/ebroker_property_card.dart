import 'package:flutter/material.dart';
import '../theme/ebroker_design.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';
import 'property_card_gallery.dart';
import 'property_type_icon.dart';

class EbrokerPropertyHorizontalCard extends StatelessWidget {
  const EbrokerPropertyHorizontalCard({required this.title, required this.price, required this.currency,
    required this.onTap, this.imageUrl, this.location, this.purposeLabel, this.categoryLabel = 'عقار',
    this.facts = const [], this.trailing, this.unavailable = false, this.embedded = false, this.imageFirst = false,
    this.imageUrls = const [], this.isSpotlight = false, this.propertyType, this.supportingText = const [], this.priceSuffix, super.key});
  final String title, price, currency, categoryLabel;
  final VoidCallback onTap;
  final String? imageUrl, location, purposeLabel, propertyType, priceSuffix;
  final List<String> imageUrls, supportingText;
  final List<AppPropertyFact> facts;
  final Widget? trailing;
  final bool unavailable, embedded, imageFirst, isSpotlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final vertical = imageFirst || MediaQuery.textScalerOf(context).scale(14) > 20;
    Widget gallery(double height) => ClipRRect(borderRadius: BorderRadius.circular(16),
      child: PropertyCardGallery(imageUrl: imageUrl, imageUrls: imageUrls, isSpotlight: isSpotlight,
        height: height, overlay: trailing, propertyType: propertyType ?? propertyTypeFromLabel(categoryLabel)));
    final detail = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [PropertyTypeIcon(type: propertyType, label: categoryLabel, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5), Text(categoryLabel, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))]),
        if (purposeLabel != null) EbrokerPurposeLabel(purposeLabel!),
      ]),
      const SizedBox(height: 8), Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
      if (location?.trim().isNotEmpty == true) ...[const SizedBox(height: 7), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.location_on_outlined, size: 15, color: scheme.onSurfaceVariant), const SizedBox(width: 4),
        Expanded(child: Text(location!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11))),
      ])],
      const SizedBox(height: 12), AppPropertyPrice(price: price, currency: currency, suffix: priceSuffix),
    ]);
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vertical) ...[gallery(196.rh(context)), const SizedBox(height: 14), Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: detail)]
      else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 116.rw(context), child: gallery(146)),
        const SizedBox(width: 12), Expanded(child: detail)]),
      if (facts.isNotEmpty) ...[const SizedBox(height: 13), Divider(color: scheme.outlineVariant.withValues(alpha: .7)),
        const SizedBox(height: 10), AppPropertyFacts(facts: facts)],
      if (supportingText.isNotEmpty) ...[const SizedBox(height: 10), for (final line in supportingText)
        Padding(padding: const EdgeInsets.only(top: 3), child: Text(line, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)))],
      if (unavailable) ...[const SizedBox(height: 10), const AppInlineMessage(message: 'هذا العقار غير متاح حاليًا', tone: AppStatusTone.neutral)],
    ]);
    return embedded ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22), child: Padding(padding: const EdgeInsets.all(10), child: content))
      : AppSurface(onTap: onTap, padding: const EdgeInsets.all(10), child: content);
  }
}
