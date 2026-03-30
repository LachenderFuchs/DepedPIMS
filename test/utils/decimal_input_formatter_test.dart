import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/utils/decimal_input_formatter.dart';

void main() {
  group('DecimalTextInputFormatter', () {
    test('allows plain numbers and single dot', () {
      final fmt = DecimalTextInputFormatter(decimalRange: 2);
      final old = const TextEditingValue(text: '');
      final out = fmt.formatEditUpdate(old, const TextEditingValue(text: '123.45'));
      expect(out.text, '123.45');
    });

    test('rejects multiple dots', () {
      final fmt = DecimalTextInputFormatter(decimalRange: 2);
      final old = const TextEditingValue(text: '12.3');
      final out = fmt.formatEditUpdate(old, const TextEditingValue(text: '12.3.4'));
      expect(out.text, old.text);
    });
  });

  group('MoneyInputFormatter', () {
    test('formats integer grouping', () {
      final fmt = MoneyInputFormatter(decimalRange: 2);
      final old = const TextEditingValue(text: '');
      final out = fmt.formatEditUpdate(old, const TextEditingValue(text: '1234567'));
      expect(out.text, '1,234,567');
    });

    test('preserves decimals and cursor mapping', () {
      final fmt = MoneyInputFormatter(decimalRange: 2);
      final old = const TextEditingValue(text: '');
      final newVal = const TextEditingValue(text: '1234.5', selection: TextSelection.collapsed(offset: 6));
      final out = fmt.formatEditUpdate(old, newVal);
      expect(out.text, '1,234.5');
      expect(out.selection.end, greaterThan(0));
    });
  });
}
