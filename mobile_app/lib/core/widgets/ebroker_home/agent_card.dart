// Transplanted from eBroker 1.8.0; see docs/WAVE3_HOME_SOURCE_MAP.json.
import 'package:flutter/material.dart';
import '../../../features/broker/domain/broker_models.dart';
import 'source_adapters.dart';
import 'responsive_size.dart';

class EbrokerHomeAgentCard extends StatelessWidget {
  const EbrokerHomeAgentCard({required this.profile, required this.onTap, this.width = 285, super.key});
  final BrokerProfile profile;
  final VoidCallback onTap;
  final double width;
  @override
  Widget build(BuildContext context) {
    final resolvedHeroTag = 'home-agent-${profile.id}';
    final largeText = MediaQuery.textScalerOf(context).scale(11.5) > 18;
    final ratingLabel = profile.ratingCount == 0 ? 'لا تقييمات بعد'
      : '${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييم';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: EdgeInsets.all(12.rw(context)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.rw(context)),
          color: context.sourceColors.secondaryColor,
          border: Border.all(
            color: context.sourceColors.borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 198.rh(context),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 152.rh(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.rw(context)),
                      child: Hero(
                        tag: '$resolvedHeroTag-banner',
                        child: DecoratedBox(decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [context.sourceColors.tertiaryColor.withValues(alpha: .13),
                            context.sourceColors.tertiaryColor.withValues(alpha: .03)]))),
                      ),
                    ),
                  ),
                  if (!largeText) PositionedDirectional(
                    end: 4.rw(context),
                    top: 162.rh(context),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.rw(context),
                        vertical: 6.rh(context),
                      ),
                      decoration: BoxDecoration(
                        color: context.sourceColors.tertiaryColor.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(8.rw(context)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SourceImage(
                            imageUrl: 'star',
                            width: 14.rw(context),
                            height: 14.rh(context),
                            color: context.sourceColors.tertiaryColor,
                          ),
                          SizedBox(width: 5.rw(context)),
                          SourceText(
                            ratingLabel,
                            fontSize: 11.5.rw(context),
                            fontWeight: FontWeight.w600,
                            color: context.sourceColors.tertiaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 6.rw(context),
                    bottom: 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          width: 70.rw(context),
                          height: 70.rw(context),
                          decoration: BoxDecoration(
                            color: context.sourceColors.secondaryColor,
                            borderRadius: BorderRadius.circular(
                              14.rw(context),
                            ),
                            border: Border.all(
                              color: context.sourceColors.secondaryColor,
                              width: 3.rw(context),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              11.rw(context),
                            ),
                            child: Hero(
                              tag: 'agent-hero-${profile.id}',
                              child: (profile.photoUrl?.isNotEmpty ?? false)
                                  ? SourceImage(
                                      height: 70.rh(context),
                                      width: 70.rw(context),
                                      imageUrl: profile.photoUrl ?? '',
                                    )
                                  : Center(
                                      child: SourceImage(
                                        imageUrl: 'defaultProfileIcon',
                                        color: context.sourceColors.tertiaryColor,
                                        width: 28.rw(context),
                                        height: 28.rh(context),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (profile.verified)
                          Positioned(
                            bottom: -5.rh(context),
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: context.sourceColors.secondaryColor, shape: BoxShape.circle),
                                child: Icon(Icons.verified, size: 13, color: context.sourceColors.tertiaryColor)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10.rh(context)),
            // Name
            Hero(
              tag: '$resolvedHeroTag-name',
              child: Material(
                type: MaterialType.transparency,
                child: SourceText(
                  profile.name,
                  fontWeight: FontWeight.w600,
                  fontSize: context.sourceFonts.md,
                  color: context.sourceColors.textColorDark,
                  maxLines: 1,
                ),
              ),
            ),
            SizedBox(height: 2.rh(context)),
            // Email
            Hero(
              tag: '$resolvedHeroTag-email',
              child: Material(
                type: MaterialType.transparency,
                child: SourceText(
                  profile.typeLabel,
                  fontSize: context.sourceFonts.xs,
                  fontWeight: FontWeight.w400,
                  color: context.sourceColors.textLightColor,
                  maxLines: 1,
                ),
              ),
            ),
            SizedBox(height: 10.rh(context)),
            if (largeText) Padding(padding: const EdgeInsets.only(bottom: 8),
              child: SourceText(ratingLabel, fontSize: 11.5, color: context.sourceColors.tertiaryColor)),
            // Property & Project counts
            Container(
              padding: EdgeInsets.symmetric(
                vertical: 8.rh(context),
                horizontal: 6.rw(context),
              ),
              decoration: BoxDecoration(
                color: context.sourceColors.textLightColor.withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(8.rw(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: SourceText(
                        'عقارات: ${profile.activeListings}',
                        fontSize: 12.rw(context),
                        fontWeight: FontWeight.w500,
                        color: context.sourceColors.textColorDark,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  Container(
                    width: 1.2.rw(context),
                    height: 16.rh(context),
                    color: context.sourceColors.textColorDark.withValues(
                      alpha: 0.25,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SourceText(
                        'صفقات مؤكدة: ${profile.completedDeals}',
                        fontSize: 12.rw(context),
                        fontWeight: FontWeight.w500,
                        color: context.sourceColors.textColorDark,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onTap, child: const Text('عرض الملف والتواصل')),

          ],
        ),
      ),
    );
  }
}
