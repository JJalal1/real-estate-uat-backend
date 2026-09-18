abstract final class V2Package {
  static const code =
      String.fromEnvironment('V2_PACKAGE', defaultValue: 'P01');

  static const title = 'الأساس والهوية';
  static const label = 'الحزمة الأولى';

  static String get displayLabel => '$code • $title';
}
