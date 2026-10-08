import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss', 'ar_EG');
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd', 'ar_EG');
  static final DateFormat _timeFormat = DateFormat('HH:mm', 'ar_EG');
  static final DateFormat _displayDateFormat = DateFormat('d MMMM yyyy', 'ar_EG');
  static final DateFormat _displayDateTimeFormat = DateFormat('d MMMM yyyy، HH:mm', 'ar_EG');
  static final DateFormat _isoFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", 'ar_EG');

  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormat.format(dateTime);
  }

  static String formatDate(DateTime dateTime) {
    return _dateFormat.format(dateTime);
  }

  static String formatTime(DateTime dateTime) {
    return _timeFormat.format(dateTime);
  }

  static String formatDisplayDate(DateTime dateTime) {
    return _displayDateFormat.format(dateTime);
  }

  static String formatDisplayDateTime(DateTime dateTime) {
    return _displayDateTimeFormat.format(dateTime);
  }

  static String toIsoString(DateTime dateTime) {
    return _isoFormat.format(dateTime.toUtc());
  }

  static DateTime parseDateTime(String isoString) {
    return DateTime.parse(isoString).toLocal();
  }

  static DateTime parseDate(String dateString) {
    return DateTime.parse(dateString);
  }
}