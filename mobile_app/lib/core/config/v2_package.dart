abstract final class V2Package {
  static const code =
      String.fromEnvironment('V2_PACKAGE', defaultValue: 'P02');

  static const title = 'السوق والبحث';
  static const label = 'الحزمة الثانية';

  static String get displayLabel => '$code • $title';
}
