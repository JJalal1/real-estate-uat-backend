import 'package:flutter/material.dart';

import '../theme/ebroker_design.dart';
import 'ebroker_widgets.dart';

/// Presentation port of eBroker 1.8.0 AddListingButton, using its original
/// shape/plus assets and independent scale, shape and plus animations.
class EbrokerAddListingButton extends StatelessWidget {
  const EbrokerAddListingButton({
    required this.isOpen,
    required this.onPressed,
    super.key,
  });

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    Duration duration(int milliseconds) => reducedMotion
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
    final label = isOpen ? 'إغلاق خيارات الإعلان' : 'إضافة عقار';

    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          key: const ValueKey('home-add-property'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 56.rw(context),
            height: 56.rh(context),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (Theme.of(context).brightness == Brightness.light)
                  Container(
                    height: 48.rh(context),
                    width: 46.rw(context),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99999),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4D5454).withValues(alpha: .5),
                          offset: const Offset(0, -1.5),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                AnimatedScale(
                  scale: isOpen ? 1.15 : 1,
                  duration: duration(200),
                  child: AnimatedRotation(
                    turns: isOpen ? 1 / 3 : 0,
                    duration: duration(500),
                    child: EbrokerImage(
                      'add_shape',
                      size: 56.rw(context),
                      color: EbrokerDesign.templateBrand,
                    ),
                  ),
                ),
                Center(
                  child: AnimatedRotation(
                    turns: isOpen ? 135 / 360 : 0,
                    duration: duration(400),
                    child: EbrokerImage(
                      'plus_btn',
                      size: 18.rw(context),
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
