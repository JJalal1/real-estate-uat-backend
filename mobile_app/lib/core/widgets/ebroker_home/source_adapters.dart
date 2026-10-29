import 'package:flutter/material.dart';

import '../../../features/properties/domain/property_details.dart';
import '../app_components.dart';
import '../ebroker_widgets.dart';
import '../property_type_icon.dart';
import '../viewport_media.dart';

/// Presentation-only bridge for the original template widget bodies.
/// No template repository, account, tracking, paid feature or private data.
extension SourceContext on BuildContext {
  SourceColors get sourceColors => SourceColors(Theme.of(this).colorScheme);
  SourceFonts get sourceFonts => const SourceFonts();
}

class SourceColors {
  const SourceColors(this.scheme);
  final ColorScheme scheme;
  Color get secondaryColor => scheme.surface;
  Color get tertiaryColor => scheme.primary;
  Color get onTertiaryColor => scheme.onPrimary;
  Color get borderColor => scheme.outlineVariant;
  Color get textColorDark => scheme.onSurface;
  Color get textLightColor => scheme.onSurfaceVariant;
}

class SourceFonts {
  const SourceFonts();
  double get md => 16;
  double get sm => 14;
  double get xs => 12;
  double get xxs => 10;
}

class SourceText extends StatelessWidget {
  const SourceText(this.text, {this.fontSize, this.fontWeight, this.color,
    this.maxLines, this.textAlign, super.key});
  final String text;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final int? maxLines;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(text, maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis, textAlign: textAlign,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: fontSize, fontWeight: fontWeight, color: color));
}

class SourceCategory {
  const SourceCategory(this.category, this.type, {this.selected = false});
  final String? category, type;
  final bool selected;
  String? get translatedName => category;
  String? get image => 'type:${type ?? 'all'}';
}

abstract final class AppIcons {
  static const location = 'location';
}

class SourceImage extends StatelessWidget {
  const SourceImage({required this.imageUrl, this.width, this.height, this.color,
    this.loadingImageHash, super.key});
  final String imageUrl;
  final String? loadingImageHash;
  final double? width, height;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dimension = width?.isFinite == true ? width! : 18.0;
    if (imageUrl.startsWith('type:')) {
      return PropertyTypeIcon(type: imageUrl.substring(5), size: dimension, color: color);
    }
    if (imageUrl == 'star') return Icon(Icons.star_rounded, size: dimension, color: color);
    if (const ['location', 'defaultProfileIcon'].contains(imageUrl)) {
      return EbrokerImage(imageUrl, size: dimension, color: color);
    }
    // Reuse Aqer's original HTTP cache, derivative sizing, privacy and viewport
    // checks, instead of importing the template's networking/image package.
    return LayoutBuilder(builder: (context, bounds) {
      final logical = width?.isFinite == true ? width! : bounds.maxWidth;
      final pixels = (logical * MediaQuery.devicePixelRatioOf(context)).round().clamp(128, 1080).toInt();
      return SizedBox(width: width, height: height, child: ViewportMedia(
        builder: (_) => AppPropertyMedia(imageUrl: imageUrl.isEmpty ? null : imageUrl,
          height: height ?? 132, cacheWidth: pixels)));
    });
  }
}

class SourceProperty {
  const SourceProperty(this.value);
  final PropertySummary value;
  int get id => value.id;
  String? get title => value.title;
  String? get translatedTitle => value.title;
  String? get city => value.address;
  SourceCategory? get category => SourceCategory(ebrokerPropertyTypeLabel(value.type), value.type);
  String? get lowQualityTitleImage => null;
  bool get isRent => value.purpose == 'rent';
  bool get isSpotlight => value.isSpotlight;
  List<String> get images => <String>{if (value.mainImage?.isNotEmpty == true) value.mainImage!,
    ...value.imageUrls.where((url) => url.isNotEmpty)}.take(12).toList(growable: false);
  String get priceLabel => moneyLabel(isRent ? value.monthlyRent ?? value.price : value.price, value.currency);
  String get rentLabel => value.monthlyRent == null ? 'القيمة المعروضة' : 'شهريًا';
  String? get advanceLabel => isRent && value.monthlyRent != null && value.price != value.monthlyRent
    ? '${value.advanceMonths == null ? 'القيمة المعروضة' : 'مقدم ${value.advanceMonths} أشهر'}: ${moneyLabel(value.price, value.currency)}' : null;
}

class SourcePurposeLabel extends StatelessWidget {
  const SourcePurposeLabel({required this.propertyType, super.key});
  final String propertyType;
  @override
  Widget build(BuildContext context) => EbrokerPurposeLabel(propertyType == 'rent' ? 'للإيجار' : 'للبيع');
}

class SourceSpotlightBadge extends StatelessWidget {
  const SourceSpotlightBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(4)),
    child: Text('مميز', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 10)));
}
