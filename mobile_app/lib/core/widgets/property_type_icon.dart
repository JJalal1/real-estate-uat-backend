import 'package:flutter/material.dart';

String? propertyTypeFromLabel(String label) => const {
  'شقق':'apartment', 'منازل':'house', 'فلل':'villa', 'عمائر':'building', 'أراضٍ':'land', 'محلات':'shop', 'مكاتب':'office', 'مزارع':'farm',
  'شقة':'apartment', 'دور كامل':'floor', 'عمارة':'building', 'عمارة كاملة':'building', 'منزل':'house',
  'فيلا':'villa', 'أرض':'land', 'مزرعة':'farm', 'محل':'shop', 'مكتب':'office',
}[label];

IconData propertyTypeIcon(String? type) => switch (type) {
  'apartment' => Icons.apartment_rounded, 'floor' => Icons.layers_outlined,
  'building' => Icons.location_city_rounded, 'house' => Icons.home_outlined, 'villa' => Icons.villa_outlined,
  'land' => Icons.landscape_outlined, 'farm' => Icons.agriculture_outlined,
  'shop' => Icons.storefront_outlined, 'office' => Icons.business_outlined, _ => Icons.home_work_outlined,
};

class PropertyTypeIcon extends StatelessWidget {
  const PropertyTypeIcon({this.type, this.label = '', this.size = 17, this.color, super.key});
  final String? type;
  final String label;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Icon(propertyTypeIcon(type ?? propertyTypeFromLabel(label)),
    size: size, color: color ?? Theme.of(context).colorScheme.primary);
}
