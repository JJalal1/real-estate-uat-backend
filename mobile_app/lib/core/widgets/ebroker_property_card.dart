import 'package:flutter/material.dart';
import '../theme/app_typography.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';
import 'property_card_gallery.dart';
import 'property_type_icon.dart';

class EbrokerPropertyHorizontalCard extends StatelessWidget {
  const EbrokerPropertyHorizontalCard({required this.title, required this.price, required this.currency,
    required this.onTap, this.imageUrl, this.location, this.purposeLabel, this.categoryLabel = 'عقار',
    this.facts = const [], this.trailing, this.action, this.unavailable = false, this.embedded = false, this.imageFirst = false, this.preview = false, this.compactPreview = false,
    this.imageUrls = const [], this.isSpotlight = false, this.authenticatedImages = false, this.propertyType, this.supportingText = const [], this.priceSuffix, this.publicationAge, super.key});
  final String title, price, currency, categoryLabel;
  final VoidCallback onTap;
  final String? imageUrl, location, purposeLabel, propertyType, priceSuffix, publicationAge;
  final List<String> imageUrls, supportingText;
  final List<AppPropertyFact> facts;
  final Widget? trailing, action;
  final bool unavailable, embedded, imageFirst, preview, isSpotlight, authenticatedImages;
  final bool compactPreview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final vertical = preview || imageFirst || largeText;
    final compact = preview && compactPreview;
    final inset = compact ? const EdgeInsets.all(8) : const EdgeInsets.all(10);
    final titleStyle = compact ? AppTypography.propertyName.copyWith(fontSize: 16) : AppTypography.propertyName;
    final secondaryStyle = AppTypography.propertySecondary.copyWith(
      fontSize: compact ? 13 : null, color: scheme.onSurfaceVariant);
    final money = AppPropertyPrice(price: price, currency: currency, suffix: priceSuffix);
    Widget priceWithPurpose({bool fillWidth = true}) {
      final label = purposeLabel;
      if (label == null) return money;
      final badge = EbrokerPurposeLabel(label, key: const ValueKey('property-price-purpose'));
      if (largeText) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            money,
            const SizedBox(height: 4),
            Align(alignment: AlignmentDirectional.centerEnd, child: badge),
          ],
        );
      }
      return Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(fit: fillWidth ? FlexFit.tight : FlexFit.loose, child: money),
          const SizedBox(width: 8),
          badge,
        ],
      );
    }
    Widget gallery(double height) => ClipRRect(borderRadius: BorderRadius.circular(12),
      child: PropertyCardGallery(imageUrl: imageUrl, imageUrls: imageUrls, isSpotlight: isSpotlight, authenticatedImages: authenticatedImages,
        height: height, overlay: vertical ? trailing : null,
        overlayAtStart: preview && purposeLabel != null,
        purposeBadge: preview && purposeLabel != null
          ? EbrokerPurposeLabel(purposeLabel!, key: const ValueKey('property-photo-purpose'))
          : null,
        priceBadge: imageFirst && !preview ? Container(key: const ValueKey('property-photo-price'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: scheme.surface.withValues(alpha: .97), borderRadius: BorderRadius.circular(8)),
          child: priceWithPurpose(fillWidth: false)) : null,
        propertyType: propertyType ?? propertyTypeFromLabel(categoryLabel)));
    final detail = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (!imageFirst && !preview) ...[priceWithPurpose(), const SizedBox(height: 4)],
      Text(title, maxLines: largeText ? null : 2, overflow: largeText ? null : TextOverflow.ellipsis,
        style: titleStyle),
      if (location?.trim().isNotEmpty == true) ...[SizedBox(height: compact ? 3 : 4), Text(location!,
        maxLines: largeText ? null : 1, overflow: largeText ? null : TextOverflow.ellipsis,
        style: secondaryStyle)],
      if (publicationAge != null) Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(publicationAge!, style: theme.textTheme.bodySmall?.copyWith(
          fontSize: compact ? 10 : 11, color: scheme.onSurfaceVariant)),
      ),
      if (preview) ...[SizedBox(height: compact ? 4 : 6), money],
      if (!preview) ...[const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [
        PropertyTypeIcon(type: propertyType, label: categoryLabel, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4), Flexible(child: Text(categoryLabel,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant))),
      ])],
      if (facts.isNotEmpty) ...[SizedBox(height: compact ? 4 : 6), Wrap(spacing: 9, runSpacing: 4, children: [
        for (final fact in facts) Row(mainAxisSize: MainAxisSize.min, children: [Icon(fact.icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3), Flexible(child: Text(fact.label, style: (preview
            ? secondaryStyle
            : theme.textTheme.bodySmall?.copyWith(fontSize: 10))?.copyWith(color: scheme.onSurfaceVariant)))]),
      ])],
      for (final line in supportingText) Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(line, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant))),
      if (action != null) action!,
    ]);
    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vertical) ...[
        gallery(imageFirst ? (compact ? 156 : 168) : 150),
        SizedBox(height: compact ? 7 : 9),
        detail,
      ]
      else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: constraints.maxWidth < 350 ? 96 : 108, child: gallery(124)),
        const SizedBox(width: 10), Expanded(child: detail),
        if (trailing != null) trailing!,
      ]),
      if (unavailable) const Padding(padding: EdgeInsets.only(top: 8),
        child: AppInlineMessage(message: 'الإعلان غير منشور', tone: AppStatusTone.neutral)),
    ]);
    return embedded ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: inset, child: content))
      : AppSurface(onTap: onTap, padding: inset, child: content);
  });
}
