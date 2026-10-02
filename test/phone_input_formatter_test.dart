import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/ui/util/phone_input_formatter.dart';

/// The phone field cleans what is typed or pasted — and must leave the caret
/// where the person is editing. It used to jump to the end on every
/// keystroke, so fixing one digit in the middle scrambled the number.
/// (buglog B21.)
void main() {
  const f = PhoneInputFormatter();

  /// Applies an edit whose result is [text] with the caret at `|`.
  TextEditingValue edit(String marked) {
    final caret = marked.indexOf('|');
    final text = marked.replaceAll('|', '');
    return f.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
            offset: caret < 0 ? text.length : caret),
      ),
    );
  }

  String show(TextEditingValue v) =>
      '${v.text.substring(0, v.selection.extentOffset)}|'
      '${v.text.substring(v.selection.extentOffset)}';

  test('typing at the end keeps the caret at the end', () {
    expect(show(edit('98012|')), '98012|');
  });

  test('inserting a digit in the middle keeps the caret there', () {
    expect(show(edit('9807|1234501')), '9807|1234501');
  });

  test('deleting in the middle keeps the caret there', () {
    expect(show(edit('98|1234501')), '98|1234501');
  });

  test('a pasted number is cleaned; the caret ends after it', () {
    expect(show(edit('+977-9801 234 501|')), '+9779801234501|');
  });

  test('characters removed before the caret pull it back by that many', () {
    // "(980) 1|23" → the paren, the closing paren and the space disappear.
    expect(show(edit('(980) 1|23')), '9801|23');
    expect(show(edit('+977 98|01')), '+97798|01');
  });

  test('a typed separator is dropped without moving the caret forward', () {
    expect(show(edit('980-|1234')), '980|1234');
  });

  test('the leading plus counts as a kept character', () {
    expect(show(edit('+|977')), '+|977');
    expect(show(edit('|+977')), '|+977');
  });

  test('a lone plus is not a number yet: the field is emptied', () {
    final v = edit('+|');
    expect(v.text, '');
    expect(v.selection.extentOffset, 0);
  });
}
