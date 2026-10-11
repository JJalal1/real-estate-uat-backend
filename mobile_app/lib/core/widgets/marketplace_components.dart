import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/marketplace_layout.dart';

class MarketplaceSearchEntry extends StatelessWidget {
  const MarketplaceSearchEntry({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarketplaceLayout.shortcutRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.fieldMinHeight),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s16),
            child: Row(
              children: [
                Icon(Icons.search, color: scheme.primary),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    'ابحث عن موقع أو عقار',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(Icons.tune, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceActionTile extends StatelessWidget {
  const MarketplaceActionTile({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarketplaceLayout.shortcutRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: MarketplaceLayout.shortcutMinHeight,
            minWidth: AppSizes.touchTarget,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceSectionHeader extends StatelessWidget {
  const MarketplaceSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: TextButton(
              onPressed: onPressed,
              child: Text(actionLabel, textAlign: TextAlign.center),
            ),
          ),
        ],
      );
}
