import 'package:flutter/material.dart';

import '../theme/ebroker_design.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';

// home/widgets/property_horizontal_card.dart: 8px outer padding, 127px
// picture, 4px picture corners, category/title/price/location in that order.
// Only our property values and callbacks enter this presentation widget.
class EbrokerPropertyHorizontalCard extends StatelessWidget {
  const EbrokerPropertyHorizontalCard({required this.title, required this.price,
    required this.currency, required this.onTap, this.imageUrl, this.location,
    this.purposeLabel, super.key});
  final String title;
  final String price;
  final String currency;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? location;
  final String? purposeLabel;

  @override
  Widget build(BuildContext context) {
    // Keep the same card at enlarged accessibility settings; let its text
    // grow vertically rather than clipping price or disabling text scaling.
    return AppSurface(onTap: onTap, padding: const EdgeInsets.all(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 127.rw(context),
            child: AppPropertyMedia(imageUrl: imageUrl, height: 116.rh(context)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EbrokerText(purposeLabel ?? 'عقار', size: 12, weight: FontWeight.w600,
              color: EbrokerDesign.textLight),
            const SizedBox(height: 4),
            EbrokerText(title, size: 16, weight: FontWeight.w600, maxLines: 2),
            const SizedBox(height: 4),
            AppPropertyPrice(price: price, currency: currency),
            if (location != null && location!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const EbrokerImage('location', size: 12, color: EbrokerDesign.textLight),
                const SizedBox(width: 5),
                Expanded(child: EbrokerText(location!, size: 12,
                  color: EbrokerDesign.textLight, maxLines: 2)),
              ]),
            ],
          ])),
      ]));
  }
}
