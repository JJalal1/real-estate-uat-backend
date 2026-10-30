import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The approved multicolour masters retain their exact contours and colours.
// Their navy lettering needs a light backing when the surrounding theme is dark.
Widget _brandSurface(BuildContext context, Widget child) => Theme.of(context).brightness == Brightness.dark
  ? DecoratedBox(decoration: BoxDecoration(color: Theme.of(context).colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(8)), child: Padding(padding: const EdgeInsets.all(4), child: child))
  : child;

/// Canonical owner-approved house/Yemen contours; never mirror the identity in RTL.
class AqerBrandMark extends StatelessWidget {
  const AqerBrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => _brandSurface(context, SvgPicture.asset(
    'assets/brand/aqer-mark.svg', width: size, height: size,
    fit: BoxFit.contain, semanticsLabel: 'عقار', matchTextDirection: false,
  ));
}

class AqerBrandWordmark extends StatelessWidget {
  const AqerBrandWordmark({super.key, this.width = 140});
  final double width;

  @override
  Widget build(BuildContext context) => _brandSurface(context, SvgPicture.asset(
    'assets/brand/aqer-wordmark.svg', width: width, height: width * 1024 / 2760,
    fit: BoxFit.contain, semanticsLabel: 'عقار Aqer', matchTextDirection: false,
  ));
}

/// Reuses existing account-loading moments; no launch timer or artificial delay.
class AqerAccountLoading extends StatelessWidget {
  const AqerAccountLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const FittedBox(child: AqerBrandWordmark(width: 220)),
        const SizedBox(height: 28),
        Semantics(label: 'جارٍ تحميل الحساب', liveRegion: true,
          child: SizedBox.square(dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary))),
      ]),
    ),
  );
}
