import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/platform_share.dart';
import '../../../router/app_deep_links.dart';
import '../domain/property_details.dart';

Future<void> sharePublicProperty(BuildContext context, PropertyDetails property) async {
  final link = propertyPublicShareLink(property.id).toString();
  final amount = property.price.toStringAsFixed(0);
  final price = property.currency.trim().isEmpty ? amount : '$amount ${property.currency}';
  final text = 'عقار: ${property.title}\nالسعر: $price\n$link';
  try {
    await PlatformShare.text(text: text, subject: property.title);
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذرت المشاركة المباشرة، فتم نسخ رابط العقار.')),
    );
  }
}
