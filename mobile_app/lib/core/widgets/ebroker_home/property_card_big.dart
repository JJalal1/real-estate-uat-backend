// Transplanted from eBroker 1.8.0; see docs/WAVE3_HOME_SOURCE_MAP.json.
import 'package:flutter/material.dart';
import '../app_components.dart';
import 'source_adapters.dart';
import 'responsive_size.dart';
import 'image_swiper.dart';

class EbrokerHomePropertyCard extends StatelessWidget {
  const EbrokerHomePropertyCard({required this.property, required this.onTap,
    this.isFromGrid = true, this.favorite, this.action, this.facts = const [], super.key});
  final SourceProperty property;
  final VoidCallback onTap;
  final bool isFromGrid;
  final Widget? favorite, action;
  final List<AppPropertyFact> facts;
  @override
  Widget build(BuildContext context) {
    final widget = this;
    final property = widget.property;
    final isRent = property.isRent;
    final isPromoted = property.isSpotlight;
    const showFeatured = false;
    final price = property.priceLabel;
    final resolvedHeroTag = 'home-property-${property.id}';
    final propertyImages = property.images;
    final handleCardTap = onTap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: handleCardTap,
      child: Container(
        padding: EdgeInsets.all(8.rh(context)),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: context.sourceColors.secondaryColor,
          border: Border.all(
            color: context.sourceColors.borderColor,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    EbrokerHomeImageSwiper(
                      images: propertyImages,
                      heroTag: resolvedHeroTag,
                      width: double.infinity,
                      height: widget.isFromGrid
                          ? 96.rh(context)
                          : 132.rh(context),
                      borderRadius: BorderRadius.circular(4),
                      lowQualityImage: property.lowQualityTitleImage,
                      onTap: handleCardTap,
                    ),

                    if (isPromoted || showFeatured)
                      const PositionedDirectional(
                        end: 10,
                        bottom: 10,
                        child: SourceSpotlightBadge(),
                      ),
                  ],
                ),
                SizedBox(height: 8.rh(context)),
                Row(
                  children: [
                    SourceImage(
                      imageUrl: property.category?.image ?? '',
                      color: context.sourceColors.textLightColor,
                      width: 18.rw(context),
                      height: 18.rh(context),
                    ),
                    SizedBox(width: 4.rw(context)),
                    Expanded(
                      child: SourceText(
                        property.category?.translatedName ??
                            property.category?.category ??
                            '',
                        fontWeight: FontWeight.w600,
                        fontSize: context.sourceFonts.xs,
                        color: context.sourceColors.textLightColor,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.rh(context)),
                SourceText(
                  property.translatedTitle ?? property.title ?? '',
                  maxLines: 1,
                  fontSize: context.sourceFonts.md,
                  fontWeight: FontWeight.w600,
                  color: context.sourceColors.textColorDark,
                ),
                if (property.city != '') ...[
                  SizedBox(height: 8.rh(context)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SourceImage(
                        imageUrl: AppIcons.location,
                        height: 18.rh(context),
                        width: 18.rw(context),
                        color: context.sourceColors.textLightColor,
                      ),
                      SizedBox(width: 5.rw(context)),
                      Flexible(child: SourceText(
                        property.city ?? '',
                        maxLines: 1,
                        color: context.sourceColors.textLightColor,
                        fontSize: context.sourceFonts.xs,
                        fontWeight: FontWeight.w400,
                      )),
                    ],
                  ),
                ],
                SizedBox(height: 8.rh(context)),
                Divider(height: 1, color: context.sourceColors.borderColor),
                SizedBox(height: 8.rh(context)),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildPrice(
                        context,
                        price,
                        isRent,
                        resolvedHeroTag,
                      ),
                    SourcePurposeLabel(
                      propertyType: isRent ? 'rent' : 'sell',
                    ),
                  ],
                ),
                if (widget.facts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final fact in widget.facts) Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(fact.icon, size: 13, color: context.sourceColors.textLightColor),
                      const SizedBox(width: 3), Flexible(child: SourceText(fact.label, fontSize: 10, maxLines: 1)),
                    ]),
                  ]),
                ],
                if (property.advanceLabel != null) SourceText(property.advanceLabel!, fontSize: 10),
                if (widget.action != null) widget.action!,
              ],
            ),
            if (widget.favorite != null)
              PositionedDirectional(
                end: 4.rw(context),
                top: 4.rh(context),
                child: SizedBox(
                  height: 48,
                  width: 48,
                  child: widget.favorite,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrice(BuildContext context, String price, bool isRent, String resolvedHeroTag) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SourceText(price, fontWeight: FontWeight.w500, fontSize: 12, color: context.sourceColors.tertiaryColor),
      if (isRent) SourceText(property.rentLabel, fontSize: context.sourceFonts.xxs,
        color: context.sourceColors.tertiaryColor),
    ]);
}
