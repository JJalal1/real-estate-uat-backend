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
    this.purposeLabel, this.categoryLabel = 'عقار', super.key});
  final String title;
  final String price;
  final String currency;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? location;
  final String? purposeLabel;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final enlarged = MediaQuery.textScalerOf(context).scale(14) > 20;
    final amount = AppPropertyPrice(price: price, currency: currency);
    return AppSurface(onTap: onTap, padding: EdgeInsets.all(8.rh(context)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 127.rw(context),
            child: AppPropertyMedia(imageUrl: imageUrl, height: 116.rh(context)))),
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
      ]));
  }
}
