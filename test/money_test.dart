import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/domain/money.dart';

/// Covers Money.format's per-currency behavior. The NPR case is a regression
/// guard: it must keep rendering exactly as it did before USD support was
/// added (Rs prefix, en-IN lakh/crore digit grouping).
void main() {
  group('Money.format', () {
    test('NPR: Rs prefix with en-IN (lakh/crore) grouping', () {
      expect(Money.format(180000, Currency.npr), 'Rs 1,80,000');
      expect(Money.format(1500, Currency.npr), 'Rs 1,500');
      expect(Money.format(0, Currency.npr), 'Rs 0');
    });

    test('USD: \$ prefix with en-US (thousands) grouping', () {
      expect(Money.format(1234567, Currency.usd), r'$1,234,567');
      expect(Money.format(1500, Currency.usd), r'$1,500');
      expect(Money.format(0, Currency.usd), r'$0');
    });

    test('grouped() omits the symbol', () {
      expect(Money.grouped(180000, Currency.npr), '1,80,000');
      expect(Money.grouped(1234567, Currency.usd), '1,234,567');
    });
  });

  group('Currency.symbol', () {
    test('npr is "Rs " (with trailing space); usd is "\$" (no space)', () {
      expect(Currency.npr.symbol, 'Rs ');
      expect(Currency.usd.symbol, r'$');
    });
  });
}
