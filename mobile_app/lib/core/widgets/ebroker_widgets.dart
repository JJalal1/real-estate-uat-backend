import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/ebroker_design.dart';

class EbrokerIcon extends StatelessWidget {
  const EbrokerIcon(this.icon, {this.size, this.color, this.semanticLabel, this.textDirection, super.key});
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  String? get _asset {
    if ([Icons.home_work_outlined, Icons.home_outlined, Icons.home, Icons.travel_explore_outlined].contains(icon)) return 'home';
    if ([Icons.person_outline, Icons.account_circle_outlined, Icons.person].contains(icon)) return 'profile_outlined';
    if ([Icons.chat_outlined, Icons.chat_bubble_outline, Icons.chat_bubble_outline_rounded].contains(icon)) return 'chat';
    if ([Icons.search, Icons.search_rounded].contains(icon)) return 'search';
    if ([Icons.favorite_border, Icons.favorite_border_rounded].contains(icon)) return 'heart';
    if ([Icons.favorite, Icons.favorite_rounded].contains(icon)) return 'heart_filled';
    if ([Icons.notifications_outlined, Icons.notifications_none_outlined].contains(icon)) return 'notification';
    if ([Icons.location_on_outlined, Icons.location_on, Icons.location_on_rounded].contains(icon)) return 'location';
    if ([Icons.map_outlined, Icons.map].contains(icon)) return 'propertymap';
    if ([Icons.filter_list, Icons.tune, Icons.tune_rounded].contains(icon)) return 'filter';
    if ([Icons.add, Icons.add_home_outlined, Icons.add_home_work_outlined].contains(icon)) return 'plus_btn';
    if ([Icons.calendar_month_outlined, Icons.event_available_outlined].contains(icon)) return 'calendar';
    if ([Icons.inventory_2_outlined, Icons.apartment_outlined].contains(icon)) return 'properties';
    if ([Icons.edit_outlined, Icons.edit].contains(icon)) return 'edit';
    if ([Icons.phone_outlined, Icons.phone, Icons.call_outlined].contains(icon)) return 'call';
    if (icon == Icons.send) return 'send';
    if (icon == Icons.logout) return 'logout';
    if ([Icons.ios_share_outlined, Icons.share_outlined].contains(icon)) return 'share_icon';
    return null;
  }
  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) return Icon(icon, size: size, color: color, semanticLabel: semanticLabel, textDirection: textDirection);
    return Semantics(label: semanticLabel, child: EbrokerImage(asset,
      size: size ?? IconTheme.of(context).size ?? 24,
      color: color ?? IconTheme.of(context).color ?? EbrokerDesign.text));
  }
}

// Presentation ports of the purchased eBroker 1.8.0 widgets. The widget trees,
// measurements and asset paths come from that pinned source; callbacks and
// validation are supplied by our existing application, never template Cubits.
class EbrokerImage extends StatelessWidget {
  const EbrokerImage(this.name, {this.size = 24, this.color, super.key});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/ebroker/svg/$name.svg', width: size, height: size,
    colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}

// utils/custom_text.dart: height 1.3, responsive sizes and weight come from
// the template. Manrope is the primary family, Arabic uses the device fallback.
class EbrokerText extends StatelessWidget {
  const EbrokerText(this.text, {this.size = 14, this.weight = FontWeight.w400,
    this.color, this.maxLines = 10, this.align, super.key});
  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  final int maxLines;
  final TextAlign? align;
  @override
  Widget build(BuildContext context) => Text(text,
    maxLines: maxLines, overflow: TextOverflow.ellipsis, softWrap: true,
    textAlign: align,
    style: TextStyle(fontFamily: 'PrimaryFont', fontFamilyFallback: const ['NotoSansArabic', 'Arial', 'sans-serif'], fontSize: size.rf(context),
      fontWeight: weight, color: color ?? EbrokerDesign.text, height: 1.3),
  );
}

// utils/ui_utils.dart::buildButton. MaterialButton is deliberately retained.
class EbrokerButton extends StatelessWidget {
  const EbrokerButton({required this.onPressed, required this.child,
    this.icon, this.style, this.outlined = false, this.tonal = false,
    this.loading = false, this.expand = false, super.key});
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool outlined;
  final bool tonal;
  final bool loading;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final states = <WidgetState>{if (onPressed == null || loading) WidgetState.disabled};
    final foreground = style?.foregroundColor?.resolve(states) ??
      (outlined || tonal ? scheme.primary : Colors.white);
    final background = style?.backgroundColor?.resolve(states) ??
      (outlined ? Colors.white : tonal ? scheme.primaryContainer : scheme.primary);
    return MaterialButton(
      focusElevation: 0, hoverElevation: 0, highlightElevation: 0,
      minWidth: expand ? double.infinity : null,
      height: 56.rh(context),
      padding: style?.padding?.resolve(states) ?? const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(
        side: outlined ? BorderSide(color: scheme.primary) : BorderSide.none,
        borderRadius: BorderRadius.circular(4),
      ),
      elevation: outlined ? 0 : 0.5, color: background, disabledColor: background,
      textColor: foreground, disabledTextColor: foreground,
      onPressed: loading || onPressed == null ? null : () {
        FocusManager.instance.primaryFocus?.unfocus(); onPressed!();
      },
      child: DefaultTextStyle(
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: 'PrimaryFont', fontFamilyFallback: const ['NotoSansArabic', 'Arial', 'sans-serif'], fontSize: 18.rf(context),
          color: foreground, height: 1.3),
        child: IconTheme(data: IconThemeData(color: foreground, size: 20),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground)),
              if (icon != null && !loading) ...[icon!, const SizedBox(width: 4)],
              if (!loading) Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class EbrokerFilledButton extends EbrokerButton {
  const EbrokerFilledButton({required super.onPressed, required super.child, super.style, super.key});
  const EbrokerFilledButton.icon({required super.onPressed, required Widget label,
    required super.icon, super.style, super.key}) : super(child: label);
  const EbrokerFilledButton.tonal({required super.onPressed, required super.child,
    super.style, super.key}) : super(tonal: true);
  const EbrokerFilledButton.tonalIcon({required super.onPressed, required Widget label,
    required super.icon, super.style, super.key}) : super(child: label, tonal: true);
}
class EbrokerOutlinedButton extends EbrokerButton {
  const EbrokerOutlinedButton({required super.onPressed, required super.child,
    super.style, super.key}) : super(outlined: true);
  const EbrokerOutlinedButton.icon({required super.onPressed, required Widget label,
    required super.icon, super.style, super.key}) : super(child: label, outlined: true);
}

// add_property/steps/step2_property_details_screen.dart::_buildPropertyTypeOption.
// The original radio option replaces Material 3 segmented controls, while the
// values, disabled states and callbacks remain those of the calling workflow.
class EbrokerSegmentedButton<T> extends StatelessWidget {
  const EbrokerSegmentedButton({required this.segments, required this.selected,
    required this.onSelectionChanged, this.showSelectedIcon = true,
    this.emptySelectionAllowed = false, super.key});
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool showSelectedIcon;
  final bool emptySelectionAllowed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget option(ButtonSegment<T> segment) {
      final active = selected.contains(segment.value);
      final enabled = onSelectionChanged != null && segment.enabled;
      return Semantics(button: true, selected: active, enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? () => onSelectionChanged!(
            active && emptySelectionAllowed ? <T>{} : {segment.value}) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: EbrokerDesign.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: active ? primary : EbrokerDesign.border,
                width: active ? 1.5 : 1)),
            child: DefaultTextStyle(
              style: TextStyle(fontFamily: 'PrimaryFont',
                fontFamilyFallback: const ['NotoSansArabic', 'Arial', 'sans-serif'],
                fontSize: 14.rf(context), height: 1.3, color: EbrokerDesign.text,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400),
              child: Row(children: [
                if (showSelectedIcon) ...[
                  Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20, color: active ? primary : EbrokerDesign.textLight),
                  SizedBox(width: 8.rh(context)),
                ],
                if (segment.icon != null) ...[segment.icon!, SizedBox(width: 8.rh(context))],
                if (segment.label != null) Expanded(child: segment.label!),
              ]),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 400 && MediaQuery.textScalerOf(context).scale(14) > 20;
      if (stacked) return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) SizedBox(height: 12.rh(context)), option(segments[i]),
        ]]);
      return Row(children: [for (var i = 0; i < segments.length; i++) ...[
        if (i > 0) SizedBox(width: 12.rh(context)), Expanded(child: option(segments[i])),
      ]]);
    });
  }
}

// filter_screen.dart::_buildOptionChip: original 12/8 padding, 4px corners,
// solid selected brand and 5% neutral background. Workflow state stays outside.
class EbrokerChoiceChip extends StatelessWidget {
  const EbrokerChoiceChip({required this.label, required this.selected,
    required this.onSelected, this.avatar, super.key});
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: selected,
    enabled: onSelected != null,
    child: GestureDetector(onTap: onSelected == null ? null : () => onSelected!(!selected),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : EbrokerDesign.text.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(4)),
        child: DefaultTextStyle(style: TextStyle(fontFamily: 'PrimaryFont',
          fontFamilyFallback: const ['NotoSansArabic', 'Arial', 'sans-serif'],
          fontSize: 14.rf(context), height: 1.3,
          color: selected ? Colors.white : EbrokerDesign.text),
          child: IconTheme(data: IconThemeData(color: selected ? Colors.white : EbrokerDesign.text),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (avatar != null) ...[avatar!, const SizedBox(width: 8)],
              Flexible(child: label),
            ])),
        ),
      ),
    ),
  );
}

class EbrokerFilterChip extends EbrokerChoiceChip {
  const EbrokerFilterChip({required super.label, required super.selected,
    required super.onSelected, super.avatar, super.key});
}

class EbrokerActionChip extends StatelessWidget {
  const EbrokerActionChip({required this.label, required this.onPressed,
    this.avatar, super.key});
  final Widget label;
  final VoidCallback? onPressed;
  final Widget? avatar;
  @override
  Widget build(BuildContext context) => EbrokerChoiceChip(label: label,
    avatar: avatar, selected: false,
    onSelected: onPressed == null ? null : (_) => onPressed!());
}

// add_property/steps/step1_categories_screen.dart category tile, fed by our
// existing taxonomy instead of the template's remote category/Cubit model.
class EbrokerWizardCategoryCard extends StatelessWidget {
  const EbrokerWizardCategoryCard({required this.label, required this.icon,
    required this.selected, required this.onTap, super.key});
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(button: true, selected: selected, enabled: onTap != null,
      child: GestureDetector(onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(color: selected ? primary : EbrokerDesign.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? primary : EbrokerDesign.border.withValues(alpha: .7))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            EbrokerImage(icon, size: 28.rw(context), color: selected ? Colors.white : EbrokerDesign.text),
            SizedBox(height: 6.rh(context)),
            EbrokerText(label, size: 12, weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : EbrokerDesign.text, align: TextAlign.center, maxLines: 1),
          ]),
        ),
      ),
    );
  }
}

// Keep the purchased fallback composition, using our identity rather than
// displaying the template vendor's eBroker wordmark in our marketplace.
class EbrokerPropertyPlaceholder extends StatelessWidget {
  const EbrokerPropertyPlaceholder({this.size = 56, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ColoredBox(color: EbrokerDesign.page,
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      EbrokerImage('home_active', size: size, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 4),
      EbrokerText('عقارات حولك', size: 12, align: TextAlign.center,
        color: Theme.of(context).colorScheme.primary),
    ])));
}

// home/widgets/header_card.dart::TitleHeader.
class EbrokerTitleHeader extends StatelessWidget {
  const EbrokerTitleHeader({required this.title, this.onSeeAll, this.action = 'عرض الكل', super.key});
  final String title;
  final VoidCallback? onSeeAll;
  final String action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 20, bottom: 16, start: 18, end: 18),
    child: Row(children: [
      Expanded(child: EbrokerText(title, size: 16, weight: FontWeight.w700, maxLines: 2)),
      if (onSeeAll != null) InkWell(onTap: onSeeAll,
        child: Padding(padding: const EdgeInsetsDirectional.only(start: 4),
          child: EbrokerText(action, size: 12, color: EbrokerDesign.textLight))),
    ]),
  );
}

// home/widgets/category_card.dart. Values come from our discovery taxonomy.
class EbrokerCategoryCard extends StatelessWidget {
  const EbrokerCategoryCard({required this.label, required this.icon,
    required this.onTap, this.selected = false, super.key});
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent,
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: BoxConstraints(minWidth: 100.rw(context), minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.white,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : EbrokerDesign.border),
          borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          EbrokerImage(icon, size: 18.rw(context), color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12), EbrokerText(label),
        ]),
      ),
    ),
  );
}

// home/widgets/sell_rent_label.dart.
class EbrokerPurposeLabel extends StatelessWidget {
  const EbrokerPurposeLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = label.contains('إيجار') ? Colors.amber : Colors.blue;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(48)),
      child: EbrokerText(label, size: 11, weight: FontWeight.w500, color: color));
  }
}

// profile/profile_settings/profile_tile.dart. Our callbacks/permissions survive.
class EbrokerProfileTile extends StatelessWidget {
  const EbrokerProfileTile({required this.title, this.leading, this.subtitle,
    this.trailing, this.onTap, super.key});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        if (leading != null) ...[
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: EbrokerDesign.text.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: IconTheme(data: const IconThemeData(size: 24, color: EbrokerDesign.text), child: leading!)),
          const SizedBox(width: 8),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EbrokerText(title, size: 16, weight: FontWeight.w700),
          if (subtitle != null) EbrokerText(subtitle!, size: 12, color: EbrokerDesign.textLight),
        ])),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}
