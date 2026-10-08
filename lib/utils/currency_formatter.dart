import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat('#,##0', 'ar_EG');

  static String format(double amount) {
    return '${_formatter.format(amount)} ج.م';
  }

  static String formatWithSign(double amount) {
    final sign = amount >= 0 ? '+' : '';
    return '$sign${_formatter.format(amount.abs())} ج.م';
  }
}