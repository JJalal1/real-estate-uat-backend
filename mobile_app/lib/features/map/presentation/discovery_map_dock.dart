import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

/// Presentation only. The map owns selection, permission checks and callbacks.
/// Keep the mode actions visible while contextual content can scroll above.
class DiscoveryMapDock extends StatelessWidget {
  const DiscoveryMapDock({
    required this.controls,
    required this.modeBar,
    this.preview,
    this.error,
    this.message,
    super.key,
  });

  final Widget controls;
  final Widget modeBar;
  final Widget? preview;
  final Widget? error;
  final Widget? message;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              controls,
              if (error != null) ...[
                const SizedBox(height: AppSpacing.s8),
                error!,
              ],
              if (preview != null) ...[
                const SizedBox(height: AppSpacing.s8),
                preview!,
              ],
              if (message != null) ...[
                const SizedBox(height: AppSpacing.s8),
                message!,
              ],
            ],
          );
          final stackActions = constraints.maxWidth < AppLayout.narrowBreakpoint &&
              MediaQuery.textScalerOf(context).scale(16) > 20;
          if (constraints.maxHeight < AppLayout.mapDockStickyMinHeight || stackActions) {
            return SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: AppSpacing.s8), modeBar],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(child: SingleChildScrollView(primary: false, child: content)),
              const SizedBox(height: AppSpacing.s8),
              modeBar,
            ],
          );
        },
      );
}

class DiscoveryModeBar extends StatelessWidget {
  const DiscoveryModeBar({
    required this.countText,
    required this.mapMode,
    required this.onSwitch,
    required this.onAdd,
    super.key,
  });

  final String countText;
  final bool mapMode;
  final VoidCallback onSwitch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < AppLayout.narrowBreakpoint &&
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final switchButton = AppButton(
            label: mapMode ? 'قائمة' : 'خريطة',
            icon: mapMode ? Icons.view_list_outlined : Icons.map_outlined,
            style: AppButtonStyle.tonal,
            onPressed: onSwitch,
            expand: true,
          );
          final addButton = AppButton(
            label: 'إضافة',
            icon: Icons.add_circle_outline,
            style: AppButtonStyle.outlined,
            onPressed: onAdd,
            expand: true,
          );
          return AppSurface(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(countText, textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AppSpacing.s4),
                if (stacked) ...[
                  switchButton,
                  const SizedBox(height: AppSpacing.s8),
                  addButton,
                ] else
                  Row(children: [
                    Expanded(child: switchButton),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(child: addButton),
                  ]),
              ],
            ),
          );
        },
      );
}

class DiscoveryPropertyPreview extends StatelessWidget {
  const DiscoveryPropertyPreview({
    required this.title,
    required this.price,
    required this.currency,
    required this.location,
    required this.favorite,
    required this.onFavorite,
    required this.onDetails,
    required this.onClose,
    this.imageUrl,
    super.key,
  });

  final String title;
  final String price;
  final String currency;
  final String location;
  final String? imageUrl;
  final bool favorite;
  final VoidCallback? onFavorite;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AppSurface(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
        onTap: onDetails,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                AppIconButton(tooltip: 'إغلاق', icon: Icons.close, onPressed: onClose),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSizes.propertyPreviewMedia,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    child: AppPropertyMedia(imageUrl: imageUrl, height: AppSizes.propertyPreviewMedia),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppPropertyPrice(price: price, currency: currency),
                      const SizedBox(height: AppSpacing.s8),
                      Text(location, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            AppButton(
              label: favorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
              icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              style: AppButtonStyle.tonal,
              onPressed: onFavorite,
              expand: true,
            ),
          ],
        ),
      );
}
