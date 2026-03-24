import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pims_deped/utils/decimal_input_formatter.dart';

void main() {
  group('MoneyInputFormatter', () {
    final fmt = MoneyInputFormatter(decimalRange: 2);

    test('formats grouping while typing and preserves caret', () {
      // Simulate typing '1', then '0', then '0', then '0'.
      var value = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));

      value = fmt.formatEditUpdate(value, const TextEditingValue(text: '1', selection: TextSelection.collapsed(offset: 1)));
      expect(value.text, '1');
      expect(value.selection.end, 1);

      value = fmt.formatEditUpdate(value, const TextEditingValue(text: '10', selection: TextSelection.collapsed(offset: 2)));
      expect(value.text, '10');
      expect(value.selection.end, 2);

      value = fmt.formatEditUpdate(value, const TextEditingValue(text: '100', selection: TextSelection.collapsed(offset: 3)));
      expect(value.text, '100');
      expect(value.selection.end, 3);

      value = fmt.formatEditUpdate(value, const TextEditingValue(text: '1000', selection: TextSelection.collapsed(offset: 4)));
      expect(value.text, '1,000');
      // Cursor should be after the last '0' (index 5 including comma)
      expect(value.selection.end, 5);
    });

    test('preserves decimals and caret', () {
      final old = const TextEditingValue(text: '1,234', selection: TextSelection.collapsed(offset: 5));
      final next = fmt.formatEditUpdate(old, const TextEditingValue(text: '1234.', selection: TextSelection.collapsed(offset: 5)));
      expect(next.text, '1,234.');
      expect(next.selection.end, greaterThanOrEqualTo(6));
    });

    test('leading dot becomes 0.', () {
      final v = fmt.formatEditUpdate(const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)), const TextEditingValue(text: '.', selection: TextSelection.collapsed(offset: 1)));
      expect(v.text, '0.');
      expect(v.selection.end, 2);
    });
  });
}
