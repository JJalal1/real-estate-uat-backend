import 'package:flutter/material.dart';

import 'property_details_screen.dart';
import '../domain/property_details.dart';

/// A Page keeps deep links, back, account popup isolation and route history on
/// the existing navigator. The same authorized details body owns every action.
class PropertyDetailsSheetPage extends Page<void> {
  const PropertyDetailsSheetPage({required this.propertyId, this.summary, super.key});
  final int propertyId;
  final PropertySummary? summary;

  @override
  Route<void> createRoute(BuildContext context) => ModalBottomSheetRoute<void>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    isDismissible: true,
    modalBarrierColor: Colors.black.withValues(alpha: .38),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => PropertyDetailsSheet(propertyId: propertyId, summary: summary),
  );
}

class PropertyDetailsSheet extends StatefulWidget {
  const PropertyDetailsSheet({required this.propertyId, this.summary, super.key});
  final int propertyId;
  final PropertySummary? summary;
  @override
  State<PropertyDetailsSheet> createState() => _PropertyDetailsSheetState();
}

class _PropertyDetailsSheetState extends State<PropertyDetailsSheet> {
  final _extent = DraggableScrollableController();
  @override
  void dispose() { _extent.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    key: const ValueKey('property-details-sheet'),
    controller: _extent,
    initialChildSize: .72,
    minChildSize: .38,
    maxChildSize: 1,
    expand: false,
    snap: true,
    snapSizes: const [.72],
    shouldCloseOnMinExtent: true,
    builder: (context, scroll) => AnimatedBuilder(
      animation: _extent,
      child: PropertyDetailsScreen(propertyId: widget.propertyId, initialSummary: widget.summary,
        scrollController: scroll, inSheet: true),
      builder: (context, child) {
        final inset = (1 - ((_extent.isAttached ? _extent.size : .72) - .72) / .28).clamp(0.0, 1.0).toDouble();
        return Padding(padding: EdgeInsets.symmetric(horizontal: 10 * inset),
          child: ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(22 * inset)),
            child: child));
      },
    ),
  );
}
