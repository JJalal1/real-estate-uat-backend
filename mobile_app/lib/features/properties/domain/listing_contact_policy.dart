class ListingContactPolicy {
  const ListingContactPolicy({this.prefixes = const ['70','71','73','77','78']});
  final List<String> prefixes;

  static String normalize(String input) {
    var value = input.trim();
    for (var i = 0; i < 10; i++) { value = value.replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i'); }
    value = value.replaceAll(RegExp(r'[\s()\-]'), '');
    if (value.startsWith('+967')) return value.substring(4);
    if (value.startsWith('00967')) return value.substring(5);
    return value;
  }

  String? error(String input, {bool required = false}) {
    final value = normalize(input);
    if (value.isEmpty && !required) return null;
    return RegExp(r'^7[0-9]{8}$').hasMatch(value) && prefixes.contains(value.substring(0,2))
      ? null : 'أدخل رقم جوال يمني من 9 أرقام يبدأ بـ ${prefixes.join('، ')}.';
  }
}
