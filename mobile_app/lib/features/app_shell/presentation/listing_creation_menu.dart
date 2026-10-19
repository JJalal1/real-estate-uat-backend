import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/ebroker_widgets.dart';

/// Port of the purchased AddListingOverlay, in the body's Stack so the
/// navigation bar and hexagon stay above its scrim, just like the template.
/// Only labels and callbacks replace the template's project/property flow.
class ListingCreationMenu extends StatefulWidget {
  const ListingCreationMenu({
    required this.isOpen,
    required this.onClose,
    required this.onSelected,
    super.key,
  });

  final bool isOpen;
  final VoidCallback onClose;
  final ValueChanged<bool> onSelected;

  @override
  State<ListingCreationMenu> createState() => _ListingCreationMenuState();
}

class _ListingCreationMenuState extends State<ListingCreationMenu>
    with TickerProviderStateMixin {
  late final AnimationController _projectController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    reverseDuration: const Duration(milliseconds: 400),
    value: widget.isOpen ? 1 : 0,
  );
  late final AnimationController _propertyController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 300),
    value: widget.isOpen ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _animate();
  }

  @override
  void didUpdateWidget(covariant ListingCreationMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOpen != widget.isOpen) _animate();
  }

  void _animate() {
    for (final controller in [_propertyController, _projectController]) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = widget.isOpen ? 1 : 0;
      } else if (widget.isOpen) {
        controller.forward();
      } else {
        controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _projectController.dispose();
    _propertyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_propertyController, _projectController]),
      builder: (context, _) {
        if (!widget.isOpen &&
            _propertyController.isDismissed &&
            _projectController.isDismissed) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(builder: (context, constraints) {
          final maxWidth = math.max(0.0, constraints.maxWidth - 32.rw(context));
          final manual = _measure(context, 'تعبئة يدوي', 180.rw(context), maxWidth);
          final assisted = _measure(context, 'ذكاء اصطناعي', 128.rw(context), maxWidth);
          final manualBottom = 30.rh(context);
          // Normal size retains the original 30/80 offsets and 180/128 by 44
          // pills; dimensions grow only to accommodate enlarged text.
          final assistedBottom = manualBottom + manual.height + 6.rh(context);
          final begin = -60.rh(context);
          double position(AnimationController controller, double end) =>
              begin + (end - begin) * Curves.easeIn.transform(controller.value);

          return IgnorePointer(
            ignoring: !widget.isOpen,
            child: SizedBox.expand(
              child: Stack(children: [
                if (widget.isOpen)
                  Positioned.fill(
                    child: Semantics(
                      label: 'إغلاق خيارات الإعلان',
                      button: true,
                      child: GestureDetector(
                        key: const ValueKey('create-listing-scrim'),
                        onTap: widget.onClose,
                        child: Container(color: Colors.black.withValues(alpha: .7)),
                      ),
                    ),
                  ),
                _floatingButton(
                  key: const ValueKey('create-listing-manual'),
                  bottom: position(_propertyController, manualBottom),
                  dimensions: manual,
                  screenWidth: constraints.maxWidth,
                  icon: 'properties_icon',
                  label: 'تعبئة يدوي',
                  assisted: false,
                ),
                _floatingButton(
                  key: const ValueKey('create-listing-ai'),
                  bottom: position(_projectController, assistedBottom),
                  dimensions: assisted,
                  screenWidth: constraints.maxWidth,
                  icon: 'upcoming_projects_icon',
                  label: 'ذكاء اصطناعي',
                  assisted: true,
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  Size _measure(BuildContext context, String label, double width, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        fontFamily: 'PrimaryFont', fontFamilyFallback: const ['sans-serif'],
        fontSize: 12.rf(context), fontWeight: FontWeight.w500, height: 1.3,
      )),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0.0, maxWidth - 43.rw(context)));
    final result = Size(
      math.min(maxWidth, math.max(width, painter.width + 43.rw(context))),
      math.max(44.rh(context), painter.height + 20.rh(context)),
    );
    painter.dispose();
    return result;
  }

  Widget _floatingButton({
    required Key key,
    required double bottom,
    required Size dimensions,
    required double screenWidth,
    required String icon,
    required String label,
    required bool assisted,
  }) => Positioned(
    bottom: bottom,
    left: (screenWidth - dimensions.width) / 2,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => widget.onSelected(assisted),
      child: GestureDetector(
        key: key,
        onTap: () => widget.onSelected(assisted),
        child: Container(
          width: dimensions.width,
          height: dimensions.height,
          decoration: BoxDecoration(
            color: EbrokerDesign.templateBrand,
            borderRadius: BorderRadius.circular(dimensions.height / 2),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.rw(context)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              EbrokerImage(icon, size: 20.rw(context), color: Colors.white),
              SizedBox(width: 7.rw(context)),
              Flexible(child: EbrokerText(
                label, size: 12, weight: FontWeight.w500, color: Colors.white,
                align: TextAlign.center,
              )),
            ]),
          ),
        ),
      ),
    ),
  );
}

