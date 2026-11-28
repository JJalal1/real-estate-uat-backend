import 'package:flutter/services.dart';

/// Each supported glyph maps to one code unit so the editing selection is preserved.
String latinNumericText(String text) => text.replaceAllMapped(
  RegExp('[٠-٩۰-۹٬٫]'),
  (match) {
    final code = match[0]!.codeUnitAt(0);
    if (code == 0x66b) return '.';
    if (code == 0x66c) return ',';
    return (code - (code >= 0x6f0 ? 0x6f0 : 0x660)).toString();
  },
);

final latinNumberInput = TextInputFormatter.withFunction((oldValue, newValue) =>
    newValue.copyWith(text: latinNumericText(newValue.text)));
