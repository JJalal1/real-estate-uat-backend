import 'package:flutter/material.dart';
import 'app_components.dart';
import 'property_card_gallery.dart';
import 'property_type_icon.dart';

class EbrokerPropertyHorizontalCard extends StatelessWidget {
  const EbrokerPropertyHorizontalCard({required this.title, required this.price, required this.currency,
    required this.onTap, this.imageUrl, this.location, this.purposeLabel, this.categoryLabel = 'عقار',
    this.facts = const [], this.trailing, this.action, this.unavailable = false, this.embedded = false, this.imageFirst = false,
    this.imageUrls = const [], this.isSpotlight = false, this.propertyType, this.supportingText = const [], this.priceSuffix, super.key});
  final String title, price, currency, categoryLabel;
  final VoidCallback onTap;
  final String? imageUrl, location, purposeLabel, propertyType, priceSuffix;
  final List<String> imageUrls, supportingText;
  final List<AppPropertyFact> facts;
  final Widget? trailing, action;
  final bool unavailable, embedded, imageFirst, isSpotlight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final vertical = imageFirst || largeText;
    final money = AppPropertyPrice(price: price, currency: currency, suffix: priceSuffix);
    Widget gallery(double height) => ClipRRect(borderRadius: BorderRadius.circular(12),
      child: PropertyCardGallery(imageUrl: imageUrl, imageUrls: imageUrls, isSpotlight: isSpotlight,
        height: height, overlay: vertical ? trailing : null,
        priceBadge: imageFirst ? Container(key: const ValueKey('property-photo-price'),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: scheme.surface.withValues(alpha: .97), borderRadius: BorderRadius.circular(8)),
          child: money) : null,
        propertyType: propertyType ?? propertyTypeFromLabel(categoryLabel)));
    final detail = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 7, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [PropertyTypeIcon(type: propertyType, label: categoryLabel, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4), Text(categoryLabel, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant))]),
        if (purposeLabel != null) Text(purposeLabel!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.primary)),
      ]),
      const SizedBox(height: 4), Text(title, maxLines: largeText ? null : 2, overflow: largeText ? null : TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontSize: 14, height: 1.45, fontWeight: FontWeight.w700)),
      if (location?.trim().isNotEmpty == true) ...[const SizedBox(height: 4), Text(location!,
        maxLines: largeText ? null : 1, overflow: largeText ? null : TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant))],
      if (!imageFirst) ...[const SizedBox(height: 5), money],
      if (facts.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 9, runSpacing: 4, children: [
        for (final fact in facts) Row(mainAxisSize: MainAxisSize.min, children: [Icon(fact.icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3), Flexible(child: Text(fact.label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant)))]),
      ])],
      for (final line in supportingText) Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(line, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant))),
      if (action != null) action!,
    ]);
    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vertical) ...[gallery(imageFirst ? 168 : 150), const SizedBox(height: 9), detail]
      else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: constraints.maxWidth < 350 ? 96 : 108, child: gallery(124)),
        const SizedBox(width: 10), Expanded(child: detail),
        if (trailing != null) trailing!,
      ]),
      if (unavailable) const Padding(padding: EdgeInsets.only(top: 8),
        child: AppInlineMessage(message: 'هذا العقار غير متاح حاليًا', tone: AppStatusTone.neutral)),
    ]);
    return embedded ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(10), child: content))
      : AppSurface(onTap: onTap, padding: const EdgeInsets.all(10), child: content);
  });
}
