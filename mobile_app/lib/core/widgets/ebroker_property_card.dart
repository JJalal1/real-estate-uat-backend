import 'package:flutter/material.dart';

import '../theme/ebroker_design.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';

// Purchased home/widgets/property_horizontal_card.dart presentation:
// image, category, title, location, divider, and price with purpose label.
// Values and navigation remain bound to the existing marketplace provider.
class EbrokerPropertyHorizontalCard extends StatelessWidget {
  const EbrokerPropertyHorizontalCard({required this.title, required this.price,
    required this.currency, required this.onTap, this.imageUrl, this.location,
    this.purposeLabel, this.categoryLabel = 'عقار', this.facts = const [],
    this.trailing, this.unavailable = false, this.embedded = false, this.imageFirst = false, super.key});
  final String title;
  final String price;
  final String currency;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? location;
  final String? purposeLabel;
  final String categoryLabel;
  final List<AppPropertyFact> facts;
  final Widget? trailing;
  final bool unavailable;
  final bool embedded;
  final bool imageFirst;

  @override
  Widget build(BuildContext context) {
    final enlarged = MediaQuery.textScalerOf(context).scale(14) > 20;
    final amount = AppPropertyPrice(price: price, currency: currency);
    if (imageFirst) { return AppSurface(onTap: onTap, padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: AppPropertyMedia(imageUrl: imageUrl, height: 190.rh(context), overlay: trailing)),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [amount, if (purposeLabel != null) EbrokerPurposeLabel(purposeLabel!)]),
          const SizedBox(height: 8), EbrokerText(title, size: 16, weight: FontWeight.w600, maxLines: 2),
          const SizedBox(height: 6),
          EbrokerText([categoryLabel, if (location != null && location!.isNotEmpty) location!].join(' · '),
            size: 12, color: EbrokerDesign.textLight, maxLines: 2),
          if (facts.isNotEmpty) ...[const SizedBox(height: 10), AppPropertyFacts(facts: facts)],
          if (unavailable) ...[const SizedBox(height: 8), const Text('هذا العقار غير متاح حاليًا')],
        ])),
      ])); }
    final body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 127.rw(context),
            child: AppPropertyMedia(imageUrl: imageUrl, height: 116.rh(context), overlay: trailing))),
        SizedBox(width: 8.rw(context)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              EbrokerImage('properties_icon', size: 18.rw(context), color: EbrokerDesign.textLight),
              SizedBox(width: 4.rw(context)),
              Expanded(child: EbrokerText(categoryLabel, size: 11, weight: FontWeight.w500,
                color: EbrokerDesign.textLight, maxLines: 1)),
            ]),
            SizedBox(height: 8.rh(context)),
            EbrokerText(title, size: 14, weight: FontWeight.w400, maxLines: enlarged ? 2 : 1),
            if (location != null && location!.isNotEmpty) ...[
              SizedBox(height: 4.rh(context)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                EbrokerImage('location', size: 18.rw(context), color: EbrokerDesign.textLight),
                SizedBox(width: 4.rw(context)),
                Expanded(child: EbrokerText(location!, size: 12,
                  color: EbrokerDesign.textLight, maxLines: enlarged ? 2 : 1)),
              ]),
            ],
            SizedBox(height: 8.rh(context)),
            const Divider(height: 1),
            SizedBox(height: 8.rh(context)),
            if (enlarged) ...[
              amount,
              if (purposeLabel != null) ...[
                SizedBox(height: 4.rh(context)), EbrokerPurposeLabel(purposeLabel!),
              ],
            ] else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: amount),
                if (purposeLabel != null) EbrokerPurposeLabel(purposeLabel!),
              ]),
          ])),
      ]);
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      body,
      if (facts.isNotEmpty) ...[const SizedBox(height: 8), AppPropertyFacts(facts: facts)],
      if (unavailable) ...[const SizedBox(height: 8), const AppInlineMessage(
        title: 'هذا العقار غير متاح حالياً', message: 'قد يكون الإعلان أوقف أو لم يعد منشوراً.', tone: AppStatusTone.neutral)],
    ]);
    return embedded
      ? GestureDetector(onTap: onTap, child: Padding(padding: EdgeInsets.all(8.rh(context)), child: content))
      : AppSurface(onTap: onTap, padding: EdgeInsets.all(8.rh(context)), child: content);
  }
}
