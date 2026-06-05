import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/domain/phone.dart';

void main() {
  group('normalizePhone', () {
    test('strips spaces and dashes', () {
      expect(normalizePhone('98 0123 4501'), '9801234501');
      expect(normalizePhone('980-123-4501'), '9801234501');
    });

    test('keeps a single leading plus for country codes', () {
      expect(normalizePhone('+977-9801 234 501'), '+9779801234501');
    });

    test('drops parens, dots, and stray symbols', () {
      expect(normalizePhone('(980).123.4501'), '9801234501');
    });

    test('blank stays blank; lone plus yields empty', () {
      expect(normalizePhone(''), '');
      expect(normalizePhone('   '), '');
      expect(normalizePhone('+'), '');
    });
  });

  group('phoneError', () {
    test('blank is allowed (optional field)', () {
      expect(phoneError(null), isNull);
      expect(phoneError(''), isNull);
      expect(phoneError('   '), isNull);
    });

    test('accepts a 10-digit local number', () {
      expect(phoneError('9801234501'), isNull);
      expect(phoneError('980-123-4501'), isNull);
    });

    test('accepts a +977 international number', () {
      expect(phoneError('+977 9801234501'), isNull);
    });

    test('rejects too-short numbers', () {
      expect(phoneError('98012'), isNotNull);
    });

    test('rejects too-long numbers', () {
      expect(phoneError('980123450112345'), isNotNull);
    });
  });
}
