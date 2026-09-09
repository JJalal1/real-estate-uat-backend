import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonStyle { filled, tonal, outlined, text }

enum AppStatusTone { success, warning, info, neutral, error }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AppButtonStyle.filled,
    this.expand = false,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final callback = loading ? null : onPressed;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 20),
        if (loading || icon != null) const SizedBox(width: AppSpacing.s8),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    final Widget button = switch (style) {
      AppButtonStyle.filled => FilledButton(onPressed: callback, child: child),
      AppButtonStyle.tonal => FilledButton.tonal(onPressed: callback, child: child),
      AppButtonStyle.outlined => OutlinedButton(onPressed: callback, child: child),
      AppButtonStyle.text => TextButton(onPressed: callback, child: child),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.buttonMinHeight),
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        selected: selected,
        child: SizedBox.square(
          dimension: AppSizes.touchTarget,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: selected ? scheme.primaryContainer : null,
              foregroundColor: selected ? scheme.onPrimaryContainer : null,
            ),
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixPressed,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.maxLines = 1,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixPressed;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.fieldMinHeight),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        enabled: enabled,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
          suffixIcon: suffixIcon == null
              ? null
              : IconButton(
                  tooltip: onSuffixPressed == null ? null : 'إجراء',
                  onPressed: onSuffixPressed,
                  icon: Icon(suffixIcon),
                ),
        ),
      ),
    );
  }
}

class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
      child: FilterChip(
        selected: selected,
        onSelected: onSelected,
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
    this.onTap,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: selected ? scheme.primaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? AppBorderWidths.emphasized : AppBorderWidths.standard,
      ),
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) return DecoratedBox(decoration: decoration, child: content);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: AppSizes.touchTarget,
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppLayout.surfacePadding,
        vertical: AppSpacing.s4,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      leading: leading,
      trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_left)),
      onTap: onTap,
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _semantic(context, tone);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.badgeMinHeight),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.$2),
            const SizedBox(width: AppSpacing.s4),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.$2),
            ),
          ),
        ],
      ),
    );
  }
}

class AppInlineMessage extends StatelessWidget {
  const AppInlineMessage({
    required this.message,
    this.title,
    this.tone = AppStatusTone.info,
    this.icon,
    super.key,
  });

  final String message;
  final String? title;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _semantic(context, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _toneIcon(tone), color: colors.$2),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: colors.$2),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                ],
                Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.$2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.label = 'جارٍ التحميل...', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.s12),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    this.height = 16,
    this.width,
    this.radius = AppRadii.small,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ??
        AppSemanticColors.light;
    return Semantics(
      label: 'جارٍ تحميل المحتوى',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: semantic.skeletonBase,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    this.title = 'تعذر تحميل المحتوى',
    required this.message,
    this.retryLabel = 'إعادة المحاولة',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.cloud_off_outlined,
        title: title,
        message: message,
        actionLabel: onRetry == null ? null : retryLabel,
        onAction: onRetry,
      );
}

class AppUnavailableState extends StatelessWidget {
  const AppUnavailableState({
    this.title = 'هذا العقار غير متاح حالياً',
    this.message = 'قد يكون الإعلان أُغلق أو لم يعد منشوراً.',
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.domain_disabled_outlined,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

class AppPropertyPrice extends StatelessWidget {
  const AppPropertyPrice({
    required this.price,
    required this.currency,
    this.suffix,
    super.key,
  });

  final String price;
  final String currency;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$price $currency',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
        ),
        if (suffix != null)
          Text(
            suffix!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

class AppPropertyFact {
  const AppPropertyFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AppPropertyFacts extends StatelessWidget {
  const AppPropertyFacts({required this.facts, super.key});

  final List<AppPropertyFact> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s12,
      children: facts
          .map(
            (fact) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fact.icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.s8),
                  Flexible(child: Text(fact.label)),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppPropertyMedia extends StatelessWidget {
  const AppPropertyMedia({
    this.imageUrl,
    this.height = 180,
    this.borderRadius = AppRadii.card,
    super.key,
  });

  final String? imageUrl;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: imageUrl == null || imageUrl!.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainer,
                child: Icon(
                  Icons.home_work_outlined,
                  size: 40,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: scheme.surfaceContainer,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

class AppPropertyCard extends StatelessWidget {
  const AppPropertyCard({
    required this.title,
    required this.price,
    required this.currency,
    required this.onTap,
    this.imageUrl,
    this.location,
    this.purposeLabel,
    this.facts = const [],
    this.trailing,
    this.unavailable = false,
    super.key,
  });

  final String title;
  final String price;
  final String currency;
  final String? imageUrl;
  final String? location;
  final String? purposeLabel;
  final List<AppPropertyFact> facts;
  final Widget? trailing;
  final bool unavailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.zero,
      onTap: unavailable ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppPropertyMedia(imageUrl: imageUrl),
              if (purposeLabel != null)
                PositionedDirectional(
                  top: AppSpacing.s12,
                  start: AppSpacing.s12,
                  child: AppStatusBadge(label: purposeLabel!),
                ),
              if (trailing != null)
                PositionedDirectional(
                  top: AppSpacing.s8,
                  end: AppSpacing.s8,
                  child: trailing!,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.s8),
                AppPropertyPrice(price: price, currency: currency),
                if (location != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      Expanded(
                        child: Text(
                          location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppPropertyFacts(facts: facts),
                ],
                if (unavailable) ...[
                  const SizedBox(height: AppSpacing.s12),
                  const AppInlineMessage(
                    message: 'العقار لم يعد متاحاً للعرض العام.',
                    tone: AppStatusTone.neutral,
                    icon: Icons.domain_disabled_outlined,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    required this.title,
    this.actions,
    this.bottom,
    super.key,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        AppSizes.appBarMinHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) => AppBar(
        title: Text(title),
        actions: actions,
        bottom: bottom,
        toolbarHeight: AppSizes.appBarMinHeight,
      );
}

class AppNavDestination {
  const AppNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: destinations
          .map(
            (destination) => NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: content,
        actions: actions,
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.s20),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                style: AppButtonStyle.tonal,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

(Color, Color) _semantic(BuildContext context, AppStatusTone tone) {
  final semantic = Theme.of(context).extension<AppSemanticColors>() ??
      AppSemanticColors.light;
  return switch (tone) {
    AppStatusTone.success => (semantic.successContainer, semantic.onSuccessContainer),
    AppStatusTone.warning => (semantic.warningContainer, semantic.onWarningContainer),
    AppStatusTone.info => (semantic.infoContainer, semantic.onInfoContainer),
    AppStatusTone.error => (semantic.errorContainer, semantic.onErrorContainer),
    AppStatusTone.neutral => (semantic.neutralContainer, semantic.onNeutralContainer),
  };
}

IconData _toneIcon(AppStatusTone tone) => switch (tone) {
      AppStatusTone.success => Icons.check_circle_outline,
      AppStatusTone.warning => Icons.warning_amber_rounded,
      AppStatusTone.info => Icons.info_outline,
      AppStatusTone.error => Icons.error_outline,
      AppStatusTone.neutral => Icons.circle_outlined,
    };
