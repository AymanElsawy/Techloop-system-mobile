import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.##', 'en');

/// 1234.5 -> "1,234.5 ج.م." (same Western digits as the web app).
String money(num value) => '${_money.format(value)} ج.م.';

String number(num value) => _money.format(value);

/// Day-of-month number for chart labels.
String dayNumber(int d) =>
    DateFormat('d', 'ar_EG').format(DateTime(2000, 1, d));

/// RLMs around "/" keep the day on the right in right-to-left text (a numeric date renders left-to-right otherwise).
String _rtl(String s) => s.replaceAll('/', '\u200F/\u200F');

String dayMonth(DateTime d) =>
    _rtl(DateFormat('d/M', 'ar_EG').format(d.toLocal()));
String time(DateTime d) => DateFormat('h:mm a', 'ar_EG').format(d.toLocal());
String fullDate(DateTime d) =>
    DateFormat('EEEE d MMMM y', 'ar_EG').format(d.toLocal());

/// "٢٧ سبتمبر ٢٠٢٦". Dates use ar_EG for Arabic-Indic digits; money stays Western.
String longDate(DateTime d) =>
    DateFormat('d MMMM y', 'ar_EG').format(d.toLocal());

/// "٢٧/٩/٢٠٢٦"
String shortDate(DateTime d) =>
    _rtl(DateFormat('d/M/y', 'ar_EG').format(d.toLocal()));

/// "٢٧/٩/٢٠٢٦ ٣:٠٥ م". The RLM keeps the date first in right-to-left text (two number runs would merge otherwise).
String dateTime(DateTime d) => '${shortDate(d)}\u200F ${time(d)}';

/// YYYY-MM-DD in local time (date inputs sent to the API).
String isoDay(DateTime d) => DateFormat('yyyy-MM-dd', 'en').format(d);
