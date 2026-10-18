import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/ebroker_design.dart';
import 'ebroker_widgets.dart';
import 'ebroker_property_card.dart';
import '../formatters/money.dart';
export '../formatters/money.dart';

export 'app_select_field.dart';

enum AppButtonStyle { filled, tonal, outlined, text }

enum AppStatusTone { success, warning, info, neutral, error }

class AppButton extends StatelessWidget {
  const AppButton({required this.label, required this.onPressed, this.icon,
    this.style = AppButtonStyle.filled, this.expand = false, this.loading = false, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expand;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (style == AppButtonStyle.text) return TextButton(onPressed: loading ? null : onPressed, child: Text(label));
    return EbrokerButton(onPressed: onPressed, expand: expand, loading: loading,
      outlined: style == AppButtonStyle.outlined, tonal: style == AppButtonStyle.tonal,
      icon: icon == null ? null : EbrokerIcon(icon), child: Text(label, textAlign: TextAlign.center));
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
            icon: EbrokerIcon(icon),
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
    this.helperText,
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
  final String? helperText;
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
          helperText: helperText,
          helperMaxLines: 4,
          prefixIcon: prefixIcon == null ? null : EbrokerIcon(prefixIcon),
          suffixIcon: suffixIcon == null
              ? null
              : IconButton(
                  tooltip: onSuffixPressed == null ? null : 'إجراء',
                  onPressed: onSuffixPressed,
                  icon: EbrokerIcon(suffixIcon),
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
      child: EbrokerFilterChip(
        selected: selected,
        onSelected: onSelected,
        avatar: icon == null ? null : EbrokerIcon(icon, size: 18),
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
      boxShadow: [BoxShadow(color: scheme.secondary.withValues(alpha: .035), blurRadius: 18, offset: const Offset(0, 6))],
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
  const AppListRow({required this.title, this.subtitle, this.leading,
    this.trailing, this.onTap, super.key});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => EbrokerProfileTile(title: title,
    subtitle: subtitle, leading: leading, trailing: trailing, onTap: onTap);
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
            EbrokerIcon(icon, size: 16, color: colors.$2),
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
          EbrokerIcon(icon ?? _toneIcon(tone), color: colors.$2),
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
  const AppSkeleton({this.height = 16, this.width, this.radius = AppRadii.small, super.key});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ?? AppSemanticColors.light;
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
    required this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.cloud_off_outlined,
        title: title,
        message: message,
        actionLabel: retryLabel,
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
        icon: Icons.visibility_off_outlined,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
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
    final content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EbrokerImage(icon == Icons.error_outline || icon == Icons.cloud_off_outlined
                ? 'MultiColorSvg/something_went_wrong' : 'MultiColorSvg/no_data_found_illustrator', size: 240.rs(context)),
              const SizedBox(height: AppSpacing.s12),
              EbrokerText(title, size: 22, color: scheme.primary, align: TextAlign.center),
              const SizedBox(height: AppSpacing.s8),
              EbrokerText(message, size: 16, color: EbrokerDesign.textLight, align: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.s20),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
    );
    return LayoutBuilder(builder: (context, constraints) => Center(
      child: constraints.hasBoundedHeight ? SingleChildScrollView(child: content) : content));
  }
}

class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    required this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.centerTitle = false,
    super.key,
  });

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.appBarMinHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: AppSizes.appBarMinHeight,
      title: EbrokerText(title, size: 18, weight: FontWeight.w500, maxLines: 1),
      titleSpacing: leading == null ? 16 : 0,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
    );
  }
}

class AppNavDestination {
  const AppNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({required this.destinations, required this.selectedIndex,
    required this.onSelected, this.onCreate, this.createExpanded = false, super.key});
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onCreate;
  final bool createExpanded;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 18;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard;
    final items = <Widget>[];
    for (var index = 0; index < destinations.length; index++) {
      if (onCreate != null && index == 2) items.add(Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(button: true, label: 'إضافة عقار', child: Tooltip(message: 'إضافة عقار', child: InkWell(
          key: const ValueKey('home-add-property'), customBorder: const CircleBorder(), onTap: onCreate,
          child: SizedBox.square(dimension: 62, child: Stack(alignment: Alignment.center, children: [
            EbrokerImage('add_shape', size: 58, color: scheme.primary),
            AnimatedRotation(turns: createExpanded ? .125 : 0, duration: duration,
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28)),
          ]))))),
        if (!largeText) Text('إعلان', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary)),
      ]))));
      final item = destinations[index], active = index == selectedIndex;
      items.add(Expanded(child: Semantics(button: true, selected: active, label: item.label, excludeSemantics: true,
        child: Tooltip(message: item.label, child: InkWell(onTap: () => onSelected(index), borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(duration: duration, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: active ? scheme.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                child: Icon(item.icon, size: 23, color: active ? scheme.primary : scheme.onSurfaceVariant)),
              if (!largeText) ...[const SizedBox(height: 4), Text(item.label, maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, color: active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400))],
            ])))))));
    }
    return DecoratedBox(decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outlineVariant)),
      boxShadow: [BoxShadow(color: scheme.secondary.withValues(alpha: .045), blurRadius: 24, offset: const Offset(0, -6))]),
      child: SafeArea(top: false, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [Row(children: items),
          if (largeText) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: ExcludeSemantics(
            child: Text(destinations[selectedIndex].label, style: TextStyle(color: scheme.primary), textAlign: TextAlign.center))),
        ]))));
  }
}

abstract final class AppBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.modal)),
      ),
      builder: builder,
    );
  }
}

abstract final class AppDialog {
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

class AppPropertyFact {
  const AppPropertyFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AppPropertyMedia extends StatelessWidget {
  const AppPropertyMedia({
    this.imageUrl,
    this.height = 190,
    this.badge,
    this.overlay,
    this.cacheWidth,
    this.propertyType,
    super.key,
  });

  final String? imageUrl;
  final double height;
  final Widget? badge;
  final Widget? overlay;
  final int? cacheWidth;
  final String? propertyType;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl == null || imageUrl!.isEmpty)
            EbrokerPropertyPlaceholder(type: propertyType)
          else
            Image.network(
              imageUrl!,
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => EbrokerPropertyPlaceholder(type: propertyType),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const AppSkeleton(height: 190, radius: 0);
              },
            ),
          if (badge != null)
            PositionedDirectional(top: AppSpacing.s12, start: AppSpacing.s12, child: badge!),
          if (overlay != null)
            PositionedDirectional(top: AppSpacing.s8, end: AppSpacing.s8, child: overlay!),
        ],
      ),
    );
  }
}

class AppPropertyPrice extends StatelessWidget {
  const AppPropertyPrice({required this.price, required this.currency, this.suffix, super.key});
  final String price, currency;
  final String? suffix;
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
    TextSpan(text: formatMoneyAmount(price), style: Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: 18, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
    TextSpan(text: ' ${currencyLabel(currency)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11)),
    if (suffix != null) TextSpan(text: ' $suffix', style: Theme.of(context).textTheme.bodySmall),
  ]));
}

class AppPropertyFacts extends StatelessWidget {
  const AppPropertyFacts({required this.facts, super.key});
  final List<AppPropertyFact> facts;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 7, runSpacing: 7, children: [for (final fact in facts)
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(fact.icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 5), Text(fact.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11))])),
  ]);
}

class AppPropertyCard extends StatelessWidget {
  const AppPropertyCard({
    required this.title,
    required this.price,
    required this.currency,
    required this.onTap,
    this.imageUrl,
    this.imageUrls = const [],
    this.isSpotlight = false,
    this.location,
    this.facts = const <AppPropertyFact>[],
    this.purposeLabel,
    this.categoryLabel = 'عقار',
    this.unavailable = false,
    this.trailing,
    this.horizontal = false,
    super.key,
  });

  final String title;
  final String price;
  final String currency;
  final VoidCallback onTap;
  final String? imageUrl;
  final List<String> imageUrls;
  final bool isSpotlight;
  final String? location;
  final List<AppPropertyFact> facts;
  final String? purposeLabel;
  final String categoryLabel;
  final bool unavailable;
  final Widget? trailing;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => EbrokerPropertyHorizontalCard(title: title, price: price, currency: currency,
    onTap: onTap, imageUrl: imageUrl, imageUrls: imageUrls, isSpotlight: isSpotlight, location: location,
    purposeLabel: purposeLabel, categoryLabel: categoryLabel, facts: facts, trailing: trailing,
    unavailable: unavailable, imageFirst: !horizontal);
}

(Color, Color) _semantic(BuildContext context, AppStatusTone tone) {
  final theme = Theme.of(context);
  final semantic = theme.extension<AppSemanticColors>() ?? AppSemanticColors.light;
  return switch (tone) {
    AppStatusTone.success => (semantic.successContainer, semantic.onSuccessContainer),
    AppStatusTone.warning => (semantic.warningContainer, semantic.onWarningContainer),
    AppStatusTone.info => (semantic.infoContainer, semantic.onInfoContainer),
    AppStatusTone.neutral => (semantic.neutralContainer, semantic.onNeutralContainer),
    AppStatusTone.error => (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer),
  };
}

IconData _toneIcon(AppStatusTone tone) => switch (tone) {
      AppStatusTone.success => Icons.check_circle_outline,
      AppStatusTone.warning => Icons.warning_amber_outlined,
      AppStatusTone.info => Icons.info_outline,
      AppStatusTone.neutral => Icons.info_outline,
      AppStatusTone.error => Icons.error_outline,
    };
