import 'package:flutter/material.dart';

import '../theme/ebroker_design.dart';
import 'ebroker_widgets.dart';
import 'viewport_media.dart';

const ebrokerBannerAsset = 'assets/ebroker/images/fallback_agent_banner.png';

// home/widgets/sections/slider_section.dart: 15px gap, 170 responsive height,
// full viewport, 18px side padding and the source's 8px image corners.
class EbrokerHomeBanner extends StatelessWidget {
  const EbrokerHomeBanner({required this.onTap, super.key});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 15.rh(context), left: 18, right: 18),
    child: Semantics(button: true, label: 'استكشف العقارات',
      child: GestureDetector(onTap: onTap,
        child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: Image.asset(ebrokerBannerAsset, height: 170.rs(context),
            width: double.infinity, fit: BoxFit.cover))),
    ),
  );
}

// property_details/widgets/property_header.dart. The price widget is supplied
// by the app so the display amount, currency and financial meaning stay intact.
class EbrokerPropertyHeading extends StatelessWidget {
  const EbrokerPropertyHeading({required this.category, required this.title,
    required this.purpose, required this.price, this.trailing, super.key});
  final String category;
  final String title;
  final String purpose;
  final Widget price;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final statusColor = purpose.contains('إيجار') ? Colors.amber : Colors.blue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 12.rh(context)),
      Row(children: [
        const EbrokerImage('properties_icon', color: EbrokerDesign.text),
        SizedBox(width: 10.rw(context)),
        Expanded(child: EbrokerText(category, weight: FontWeight.w500)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999),
            color: statusColor.withValues(alpha: .1)),
          child: EbrokerText(purpose, weight: FontWeight.w600, color: statusColor)),
      ]),
      SizedBox(height: 8.rh(context)),
      Row(children: [
        Expanded(child: EbrokerText(title, size: 16, weight: FontWeight.w800, maxLines: 2)),
        if (trailing != null) trailing!,
      ]),
      SizedBox(height: 6.rh(context)),
      price,
    ]);
  }
}

// property_description_section.dart: original 8px padding, 4px radius,
// title/divider/body hierarchy. Use for equivalent informational sections.
class EbrokerSectionPanel extends StatelessWidget {
  const EbrokerSectionPanel({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: EbrokerDesign.surface,
      border: Border.all(color: EbrokerDesign.border), borderRadius: BorderRadius.circular(4)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      EbrokerText(title, size: 16, weight: FontWeight.w600),
      SizedBox(height: 8.rh(context)),
      const Divider(height: 1),
      SizedBox(height: 8.rh(context)),
      child,
    ]),
  );
}

// agent_mode/cards/agent_card.dart presentation. The app has verification and
// ratings, so the source's badge/stat slots show those existing public facts.
// It does not add following, direct telephone contact or agent subscriptions.
class EbrokerAdvertiserCard extends StatelessWidget {
  const EbrokerAdvertiserCard({required this.name, required this.identity,
    required this.rating, required this.ratingCount, required this.verified,
    required this.onTap, this.width, this.photoUrl, this.completedDeals, this.activeListings, this.action, this.compact = false, super.key});
  final String name;
  final String identity;
  final double rating;
  final int ratingCount;
  final bool verified;
  final VoidCallback onTap;
  final double? width;
  final String? photoUrl;
  final int? completedDeals, activeListings;
  final bool compact;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (compact) {
      return Semantics(button: true, label: 'الملف العام للمعلن $name', child: Material(
      color: EbrokerDesign.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: EbrokerDesign.border)),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: photoUrl == null
            ? EbrokerImage('defaultProfileIcon', size: 50, color: primary)
            : SizedBox.square(dimension: 50, child: ViewportMedia(builder: (_) => Image.network(photoUrl!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => EbrokerImage('defaultProfileIcon', size: 50, color: primary))))),
          const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [Text(name, style: Theme.of(context).textTheme.titleMedium),
              if (verified) Icon(Icons.verified, color: primary, size: 18)]),
            Text(identity, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 5),
            Text(ratingCount == 0 ? 'لا توجد تقييمات بعد' : '${rating.toStringAsFixed(1)} من 5 · $ratingCount تقييمًا', style: Theme.of(context).textTheme.bodySmall),
            if (completedDeals != null && activeListings != null) Text('$activeListings عقارات متاحة · $completedDeals صفقات مؤكدة', style: Theme.of(context).textTheme.bodySmall),
            if(action!=null)action!,
            Text('عرض الملف والإعلانات', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: primary)),
          ])),
        ]),
      )),
    ));
    }
    final enlarged = MediaQuery.textScalerOf(context).scale(11.5) > 20;
    final identityLabel = EbrokerText(identity, size: 11.5, weight: FontWeight.w600,
      color: primary, maxLines: enlarged ? 2 : 1);
    final identityRow = Row(mainAxisSize: MainAxisSize.min, children: [
      EbrokerImage('following', size: 14.rw(context), color: primary),
      SizedBox(width: 5.rw(context)),
      if (enlarged) Expanded(child: identityLabel) else identityLabel,
    ]);
    return Semantics(button: true, label: 'المعلن $name',
      child: GestureDetector(onTap: onTap,
        child: Container(width: width, padding: EdgeInsets.all(12.rw(context)),
          decoration: BoxDecoration(color: EbrokerDesign.surface,
            borderRadius: BorderRadius.circular(16.rw(context)),
            border: Border.all(color: EbrokerDesign.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 198.rh(context) + (MediaQuery.textScalerOf(context).scale(11.5) - 11.5) * 4, child: Stack(clipBehavior: Clip.none, children: [
              Positioned(top: 0, left: 0, right: 0, height: 152.rh(context),
                child: ClipRRect(borderRadius: BorderRadius.circular(12.rw(context)),
                  child: Image.asset(ebrokerBannerAsset, fit: BoxFit.cover))),
              Positioned(right: 4.rw(context), top: 162.rh(context),
                child: Container(padding: EdgeInsets.symmetric(horizontal: 10.rw(context), vertical: 6.rh(context)),
                  decoration: BoxDecoration(color: primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8.rw(context))),
                  child: enlarged ? SizedBox(width: 132.rw(context), child: identityRow) : identityRow)),
              Positioned(left: 6.rw(context), bottom: 0,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                  Container(width: 70.rw(context), height: 70.rw(context),
                    decoration: BoxDecoration(color: EbrokerDesign.surface,
                      borderRadius: BorderRadius.circular(14.rw(context)),
                      border: Border.all(color: EbrokerDesign.surface, width: 3.rw(context))),
                    child: ClipRRect(borderRadius: BorderRadius.circular(11.rw(context)),
                      child: photoUrl == null ? Center(child: EbrokerImage('defaultProfileIcon', size: 28.rw(context), color: primary))
                        : ViewportMedia(builder: (_) => Image.network(photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => EbrokerImage('defaultProfileIcon', size: 28.rw(context), color: primary))))),
                  if (verified) Positioned(bottom: -5.rh(context),
                    child: Container(width: 22.rw(context), height: 22.rh(context), alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                      child: EbrokerImage('agent_badge', size: 13.rw(context), color: Colors.white))),
                ])),
            ])),
            SizedBox(height: 10.rh(context)),
            if (completedDeals != null && activeListings != null) Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Text('$completedDeals صفقات مؤكدة · $activeListings عقارات نشطة', style: Theme.of(context).textTheme.bodySmall)),
            if(action!=null)action!,
            EbrokerText(name, size: 16, weight: FontWeight.w600, maxLines: 1),
            SizedBox(height: 2.rh(context)),
            EbrokerText(identity, size: 12, color: EbrokerDesign.textLight, maxLines: 1),
            SizedBox(height: 10.rh(context)),
            Container(padding: EdgeInsets.symmetric(vertical: 8.rh(context), horizontal: 6.rw(context)),
              decoration: BoxDecoration(color: EbrokerDesign.textLight.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8.rw(context))),
              child: Row(children: [
                Expanded(child: EbrokerText(ratingCount == 0 ? 'لا توجد تقييمات بعد' : 'التقييم: ${rating.toStringAsFixed(1)}',
                  size: 12, weight: FontWeight.w500, align: TextAlign.center)),
                Container(width: 1.2.rw(context), height: 16.rh(context), color: EbrokerDesign.text.withValues(alpha: .25)),
                Expanded(child: EbrokerText('التقييمات: $ratingCount', size: 12,
                  weight: FontWeight.w500, align: TextAlign.center)),
              ])),
          ])),
      ),
    );
  }
}
