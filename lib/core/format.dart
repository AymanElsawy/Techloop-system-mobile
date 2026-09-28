import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.##', 'en');

/// 1234.5 -> "1,234.5 ج.م." (same Western digits as the web app).
String money(num value) => '${_money.format(value)} ج.م.';

String number(num value) => _money.format(value);

String dayMonth(DateTime d) => DateFormat('d/M', 'ar').format(d.toLocal());
String time(DateTime d) => DateFormat('h:mm a', 'ar').format(d.toLocal());
String fullDate(DateTime d) => DateFormat('EEEE d MMMM y', 'ar').format(d.toLocal());

/// "27 سبتمبر 2026"
String longDate(DateTime d) => DateFormat('d MMMM y', 'ar').format(d.toLocal());

/// "27/9/2026"
String shortDate(DateTime d) => DateFormat('d/M/y', 'ar').format(d.toLocal());

/// "27/9/2026 3:05 م". The RLM keeps the date first in right-to-left text (two number runs would merge otherwise).
String dateTime(DateTime d) => '${shortDate(d)}\u200F ${time(d)}';

/// YYYY-MM-DD in local time (date inputs sent to the API).
String isoDay(DateTime d) => DateFormat('yyyy-MM-dd', 'en').format(d);
