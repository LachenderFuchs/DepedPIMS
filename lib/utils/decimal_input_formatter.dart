import 'package:flutter/services.dart';

/// A [TextInputFormatter] that allows only digits and a single decimal point.
/// Optionally limits the number of fractional digits via [decimalRange].
class DecimalTextInputFormatter extends TextInputFormatter {
  final int decimalRange;
  const DecimalTextInputFormatter({this.decimalRange = 10});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Allow a single leading dot by converting to `0.`
    if (text == '.') return TextEditingValue(text: '0.', selection: TextSelection.collapsed(offset: 2));
    // Permit only digits and at most one dot
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) return oldValue;
    if (text.contains('.')) {
      final parts = text.split('.');
      if (parts.length > 2) return oldValue;
      if (decimalRange >= 0 && parts[1].length > decimalRange) return oldValue;
    }
    return newValue;
  }
}
