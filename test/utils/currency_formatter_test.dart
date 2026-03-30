import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/utils/currency_formatter.dart';

void main() {
  test('CurrencyFormatter formats amounts with default symbol', () {
    CurrencyFormatter.symbol = 'â‚±';
    expect(CurrencyFormatter.format(1234.5), 'â‚±1,234.50');
    expect(CurrencyFormatter.formatPlain(1234.5), '1,234.50');
  });

  test('CurrencyFormatter updates symbol globally', () {
    CurrencyFormatter.symbol = 'PHP ';
    expect(CurrencyFormatter.format(10.2), 'PHP 10.20');
  });
}
