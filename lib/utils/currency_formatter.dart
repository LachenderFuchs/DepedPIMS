import 'package:intl/intl.dart';

/// Shared currency formatter for the PMIS DepED app.
/// The currency symbol is configurable via [symbol] and defaults to U+20B1.
/// Call [AppState.setCurrencySymbol] to update it app-wide.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final _formatter = NumberFormat('#,##0.00', 'en_US');

  /// Current currency symbol. Updated by AppState when settings change.
  static String symbol = '\u20B1';

  /// Formats a double as currency using the current symbol.
  static String format(double amount) {
    return '$symbol${_formatter.format(amount)}';
  }

  /// Formats without the currency symbol - useful for input hints.
  static String formatPlain(double amount) {
    return _formatter.format(amount);
  }
}
