/// Represents a PDF date/time string defined in [PDF 32000-1:2008, 7.9.4 Dates](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=95)
///
/// [pdfDateString] is a PDF date string.
/// The date string should be in `D:YYYYMMDDHHmmSSOHH'mm'` format as specified in the PDF standard.
/// But this class do permissive parsing and allows missing some of the components.
/// To validate the format, use [isValidFormat].
extension type const PdfDateTime(String pdfDateString) {
  /// Creates a [PdfDateTime] from a [DateTime] object.
  PdfDateTime.fromDateTime(DateTime dateTime)
    : pdfDateString = _pdfDateStringFromYMDHMS(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        dateTime.minute,
        dateTime.second,
        timeZoneOffset: dateTime.timeZoneOffset.inMinutes,
      );

  /// Creates a [PdfDateTime] from individual date and time components.
  ///
  /// - [year] (e.g., 2025)
  /// - [month] (1-12)
  /// - [day] (1-31)
  /// - [hour] (0-23)
  /// - [minute] (0-59)
  /// - [second] (0-59)
  /// - [timeZoneOffset] is in minutes and defaults to 0 (UTC)
  PdfDateTime.fromYMDHMS(int year, int month, int day, int hour, int minute, int second, {int timeZoneOffset = 0})
    : pdfDateString = _pdfDateStringFromYMDHMS(year, month, day, hour, minute, second, timeZoneOffset: timeZoneOffset);

  /// Creates a [PdfDateTime] from a nullable PDF date string.
  ///
  /// Returns null if [pdfDateString] is null. Otherwise, creates a [PdfDateTime] instance.
  static PdfDateTime? fromPdfDateString(String? pdfDateString) =>
      pdfDateString != null ? PdfDateTime(pdfDateString) : null;

  /// Generates a PDF date string from individual date and time components.
  ///
  /// - [year] (e.g., 2025)
  /// - [month] (1-12)
  /// - [day] (1-31)
  /// - [hour] (0-23)
  /// - [minute] (0-59)
  /// - [second] (0-59)
  /// - [timeZoneOffset] is in minutes and defaults to 0 (UTC)
  static String _pdfDateStringFromYMDHMS(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second, {
    int timeZoneOffset = 0,
  }) {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    final h = hour.toString().padLeft(2, '0');
    final min = minute.toString().padLeft(2, '0');
    final s = second.toString().padLeft(2, '0');
    final String tz;
    if (timeZoneOffset == 0) {
      tz = 'Z';
    } else {
      final sign = timeZoneOffset > 0 ? '+' : '-';
      final absOffset = timeZoneOffset.abs();
      final hours = (absOffset ~/ 60).toString().padLeft(2, '0');
      final minutes = (absOffset % 60).toString().padLeft(2, '0');
      tz = "$sign$hours'$minutes'";
    }
    return 'D:$y$m$d$h$min$s$tz';
  }

  /// Year (e.g., 2025)
  int get year => _getNumber(2, 4);

  /// Month (1-12)
  int get month => _getNumber(6, 2, 1);

  /// Day (1-31)
  int get day => _getNumber(8, 2, 1);

  /// Hour (0-23).
  int get hour => _getNumber(10, 2);

  /// Minute (0-59).
  int get minute => _getNumber(12, 2);

  /// Second (0-59).
  int get second => _getNumber(14, 2);

  int get timezoneOffset {
    if (pdfDateString.length >= 17) {
      final sign = pdfDateString[16];
      if (sign == 'Z') return 0;
      final hours = _getNumber(17, 2);
      final minutes = _getNumber(20, 2);
      final offsetInMinutes = hours * 60 + minutes;
      return sign == '+'
          ? offsetInMinutes
          : sign == '-'
          ? -offsetInMinutes
          : 0;
    }
    return 0;
  }

  int _getNumber(int start, int length, [int defaultValue = 0]) {
    if (pdfDateString.length >= start + length) {
      return int.tryParse(pdfDateString.substring(start, start + length)) ?? defaultValue;
    }
    return 0;
  }

  /// UTC [DateTime] representation of the PDF date/time string.
  ///
  /// The date/time is adjusted according to the timezone offset specified in the PDF date string so that the resulting
  /// [DateTime] is in UTC.
  DateTime toDateTime() =>
      DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: timezoneOffset));

  /// Checks if the PDF date/time string is in a valid format or not.
  bool get isValidFormat => _dtRegex.hasMatch(pdfDateString);

  /// Regular expression to validate PDF date/time string format.
  static final _dtRegex = RegExp(r"^D:\d{4}(\d{2}(\d{2}(\d{2}(\d{2}(\d{2}(Z|[+\-]\d{2}'\d{2}'?)?)?)?)?)?)?$");

  /// Returns a canonicalized [PdfDateTime] with all components filled in.
  PdfDateTime canonicalize() =>
      PdfDateTime.fromYMDHMS(year, month, day, hour, minute, second, timeZoneOffset: timezoneOffset);
}
