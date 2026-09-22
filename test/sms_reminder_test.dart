import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/ui/util/sms_reminder.dart';

void main() {
  final unit = Unit(
    id: 1,
    code: 'A-01',
    tenantName: 'Maya',
    businessType: '',
    monthlyRent: 15000,
    depositAmount: 0,
    depositRefunded: false,
    isActive: true,
    createdAt: DateTime(2025),
  );
  const month = BsMonth(2083, 6);

  group('rentReminderText', () {
    test('unpaid single month quotes the amount and the month', () {
      final t = rentReminderText(unit, month, paid: false, amount: 15800);
      expect(t, contains('Rs 15,800'));
      expect(t, contains('Ashwin 2083'));
    });

    test('multi-month debt uses period wording, not one month\'s label', () {
      final t = rentReminderText(unit, month,
          paid: false, amount: 31600, months: 2);
      expect(t, contains('Rs 31,600'));
      expect(t, contains('across 2 months'));
      expect(t, isNot(contains('Ashwin')));
    });

    test('months: 1 keeps the classic single-month text', () {
      final t = rentReminderText(unit, month,
          paid: false, amount: 15800, months: 1);
      expect(t, contains('for Ashwin 2083 is due'));
    });

    test('paid ignores months and thanks for the received amount', () {
      final t = rentReminderText(unit, month,
          paid: true, amount: 15800, months: 3);
      expect(t, contains('thank you'));
      expect(t, contains('Rs 15,800'));
    });

    test('zero amount never quotes Rs 0', () {
      final t = rentReminderText(unit, month,
          paid: false, amount: 0, months: 4);
      expect(t, isNot(contains('Rs 0')));
    });
  });
}
