import 'package:flutter/services.dart';

import '../../domain/phone.dart';

/// Live-cleans a phone field: on every keystroke or paste it strips spaces,
/// dashes and parens down to digits (plus an optional leading `+`), so the
/// stored number is always tidy and SMS reminders work.
///
/// The caret stays where the person is editing: it lands after the same
/// characters it followed before the clean-up, so fixing a digit in the
/// middle of a number does not throw the cursor to the end.
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final cleaned = normalizePhone(text);
    final caret = newValue.selection.extentOffset;
    if (caret < 0 || caret >= text.length) {
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    // Characters kept from before the caret: its digits, and the leading `+`.
    final before = text.substring(0, caret);
    var offset = before.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (cleaned.startsWith('+') && before.trimLeft().startsWith('+')) offset++;
    return TextEditingValue(
      text: cleaned,
      selection:
          TextSelection.collapsed(offset: offset.clamp(0, cleaned.length)),
    );
  }
}
