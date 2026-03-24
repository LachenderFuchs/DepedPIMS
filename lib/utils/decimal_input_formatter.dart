import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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

/// Formats numeric input with grouping separators (commas) while preserving
/// a single decimal point and caret position. Intended for monetary/amount
/// text fields.
class MoneyInputFormatter extends TextInputFormatter {
  final int decimalRange;
  final NumberFormat _intFmt = NumberFormat('#,##0', 'en_US');

  MoneyInputFormatter({this.decimalRange = 10});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;
    // Allow single leading dot -> convert to 0.
    if (text == '.') return TextEditingValue(text: '0.', selection: const TextSelection.collapsed(offset: 2));

    // Remove existing commas for validation and processing
    final raw = text.replaceAll(',', '');
    // Permit only digits and optional single dot
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(raw)) return oldValue;

    // Enforce single dot and decimal range
    if (raw.contains('.')) {
      final parts = raw.split('.');
      if (parts.length > 2) return oldValue;
      if (decimalRange >= 0 && parts[1].length > decimalRange) return oldValue;
    }

    // Split integer and fractional parts
    final parts = raw.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final fracPart = parts.length > 1 ? parts[1] : null;

    // Format integer part with grouping
    final formattedInt = _intFmt.format(int.tryParse(intPart) ?? 0);
    final formatted = fracPart != null ? '$formattedInt.$fracPart' : formattedInt;

    // Map cursor position: compute number of non-comma chars before original cursor
    final origCursor = newValue.selection.end;
    final charsBefore = origCursor <= 0
        ? 0
        : text.substring(0, origCursor).replaceAll(',', '').length;

    // Find cursor index in formatted string by counting non-comma chars
    int newCursor = 0;
    int seen = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (formatted[i] != ',') seen++;
      newCursor++;
      if (seen >= charsBefore) break;
    }
    newCursor = newCursor.clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
