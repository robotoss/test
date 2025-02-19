import 'package:flutter/services.dart';

/// Example of usage:
///   TextField(
///     inputFormatters: [DateMaskTextInputFormatter(mask: 'dd/MM/yyyy')],
///     keyboardType: TextInputType.number,
///   )
///
/// Behavior overview:
///   1) The mask 'dd/MM/yyyy' means:
///      - first two characters for the day
///      - separator '/'
///      - next two characters for the month
///      - separator '/
///      - last four characters for the year
///   2) Validations:
///      - Day cannot exceed the maximum days of the given month (28/29/30/31)
///      - Month must be between 1 and 12
///      - Year is limited by [minYear] and [maxYear] (by default 1–9999)
///   3) Example: user types "2" -> returns "2|d/MM/yyyy" ( '|' is the cursor )
///      then types "22" -> returns "22/|MM/yyyy"
///   4) If the user entered day = 31 and then month = 2 (February), the day
///      will be adjusted to 28 or 29 for a leap year.
///   5) The cursor position is calculated so that it follows the user input
///      even if the user inserts or deletes digits in the middle of the text.
///
class DateMaskTextInputFormatter extends TextInputFormatter {
  final String mask;

  /// Optional range for the year
  final int minYear;
  final int maxYear;

  DateMaskTextInputFormatter({
    required this.mask,
    this.minYear = 1,
    this.maxYear = 9999,
  });

  /// Splits the mask into a list of tokens:
  ///   - 'd' (day)
  ///   - 'M' (month)
  ///   - 'y' (year)
  ///   - 'separator' (any other symbol)
  /// Example: 'dd/MM/yyyy' -> ['d', 'd', '/', 'M', 'M', '/', 'y', 'y', 'y', 'y']
  List<_MaskToken> _parseMask(String mask) {
    final tokens = <_MaskToken>[];
    for (int i = 0; i < mask.length; i++) {
      final ch = mask[i];
      if (ch == 'd' || ch == 'M' || ch == 'y') {
        tokens.add(_MaskToken(type: ch));
      } else {
        tokens.add(_MaskToken(type: 'separator', value: ch));
      }
    }
    return tokens;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the new value is empty, return empty
    if (newValue.text.isEmpty) {
      return newValue.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    // Parse mask
    final tokens = _parseMask(mask);

    // Extract digits from the new input
    final newDigits = _extractDigits(newValue.text);

    // We'll keep track of day, month, and year
    int day = 0;
    int month = 0;
    int year = 0;

    // Determine how many digits are allocated for day, month, and year
    final dayCount = tokens.where((t) => t.type == 'd').length;   // usually 2
    final monthCount = tokens.where((t) => t.type == 'M').length; // usually 2
    final yearCount = tokens.where((t) => t.type == 'y').length;  // usually 4

    // Keep track of how many digits we've processed from newDigits
    int digitIndex = 0;

    // Get day string
    final dayStr = _takeDigits(newDigits, digitIndex, dayCount);
    digitIndex += dayStr.length;
    day = dayStr.isEmpty ? 0 : int.tryParse(dayStr) ?? 0;

    // Get month string
    final monthStr = _takeDigits(newDigits, digitIndex, monthCount);
    digitIndex += monthStr.length;
    month = monthStr.isEmpty ? 0 : int.tryParse(monthStr) ?? 0;

    // Get year string
    final yearStr = _takeDigits(newDigits, digitIndex, yearCount);
    digitIndex += yearStr.length;
    year = yearStr.isEmpty ? 0 : int.tryParse(yearStr) ?? 0;

    // Validate/correct year
    if (year != 0) {
      if (year < minYear) {
        year = minYear;
      } else if (year > maxYear) {
        year = maxYear;
      }
    }

    // Validate/correct month
    if (month > 12) {
      month = 12;
    } else if (month < 1 && monthStr.isNotEmpty) {
      // If user typed '0' (or something that resolves to 0) but the string is not empty
      month = 1;
    }

    // Validate/correct day
    if (month > 0 && day > 0) {
      final maxDay = _daysInMonth(year, month);
      if (day > maxDay) {
        day = maxDay;
      } else if (day < 1 && dayStr.isNotEmpty) {
        day = 1;
      }
    }

    // Build the new formatted text by walking through the mask tokens again
    final buffer = StringBuffer();

    // We will need to keep track of how many day, month, and year digits we've already used
    int usedDayDigits = 0;
    int usedMonthDigits = 0;
    int usedYearDigits = 0;

    // Convert day, month, year to fixed-length strings
    final dayFormatted = _intToFixedString(day, dayCount);
    final monthFormatted = _intToFixedString(month, monthCount);
    final yearFormatted = _intToFixedString(year, yearCount);

    for (final token in tokens) {
      if (token.type == 'd') {
        buffer.write(dayFormatted[usedDayDigits]);
        usedDayDigits++;
      } else if (token.type == 'M') {
        buffer.write(monthFormatted[usedMonthDigits]);
        usedMonthDigits++;
      } else if (token.type == 'y') {
        buffer.write(yearFormatted[usedYearDigits]);
        usedYearDigits++;
      } else {
        // separator
        buffer.write(token.value);
      }
    }

    final finalText = buffer.toString();

    // Calculate the new cursor position based on how many digits are to the left of
    // the original selection in the newValue (unformatted). This ensures the cursor
    // follows the user's input.
    final newCursorPos = _calculateCursorPosition(newValue, finalText);

    return TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }

  /// Removes any non-digit characters from the input
  String _extractDigits(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Takes [count] digits from [digits] starting at [start]. If not enough digits remain, take what's available.
  String _takeDigits(String digits, int start, int count) {
    if (start >= digits.length) {
      return '';
    }
    final end = (start + count) > digits.length ? digits.length : (start + count);
    return digits.substring(start, end);
  }

  /// Returns the number of days in a given [month] for [year], accounting for leap years in February.
  int _daysInMonth(int year, int month) {
    if (month < 1 || month > 12) return 31;
    // February
    if (month == 2) {
      return _isLeapYear(year) ? 29 : 28;
    }
    // Apr, Jun, Sep, Nov -> 30
    if ([4, 6, 9, 11].contains(month)) {
      return 30;
    }
    return 31;
  }

  /// Checks if a year is leap year
  bool _isLeapYear(int year) {
    if (year == 0) return false; // not enough digits to determine
    return (year % 400 == 0) || ((year % 4 == 0) && (year % 100 != 0));
  }

  /// Converts [value] to a string of length [width], padded with '0'.
  /// If [value] == 0, we return a placeholder like '___'.
  /// This is to indicate the field is not fully entered yet.
  String _intToFixedString(int value, int width) {
    if (value == 0) {
      // Return placeholder
      return '_' * width;
    }
    return value.toString().padLeft(width, '0');
  }

  /// Calculates the new cursor position so that it follows
  /// the user's input. We look at how many digits are to the left of
  /// the selection in [newValue], then position the cursor at the
  /// corresponding digit index in the formatted [finalText].
  int _calculateCursorPosition(TextEditingValue newValue, String finalText) {
    // Count how many digits were typed before the current cursor in newValue
    final rawText = newValue.text; // unformatted text (with possible separators)
    final cursorIndex = newValue.selection.start;

    // How many digits are to the left of cursorIndex in rawText?
    int digitCountBeforeCursor = 0;
    for (int i = 0; i < cursorIndex && i < rawText.length; i++) {
      if (RegExp(r'[0-9]').hasMatch(rawText[i])) {
        digitCountBeforeCursor++;
      }
    }

    // Now, we walk through finalText (the formatted text) and find
    // the position that corresponds to digitCountBeforeCursor
    int currentDigitCount = 0;
    for (int i = 0; i < finalText.length; i++) {
      if (RegExp(r'[0-9_]').hasMatch(finalText[i])) {
        // We treat digits and placeholders '_' as digit positions
        if (currentDigitCount == digitCountBeforeCursor) {
          // Place the cursor right here
          return i;
        }
        currentDigitCount++;
      }
    }

    // If we reach the end without placing the cursor,
    // it means the user typed more digits than fit, or
    // the cursor is beyond all digits. Just put cursor at the end.
    return finalText.length;
  }
}

/// Helper class to describe a mask token.
/// [type] can be 'd', 'M', 'y', or 'separator'
/// [value] holds the separator character if it's a separator
class _MaskToken {
  final String type;  // 'd', 'M', 'y', 'separator'
  final String value;

  _MaskToken({required this.type, this.value = ''});
}
