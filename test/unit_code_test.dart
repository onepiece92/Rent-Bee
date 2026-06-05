import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/domain/unit_code.dart';

void main() {
  group('suggestUnitCode', () {
    test('empty list defaults to A-01', () {
      expect(suggestUnitCode([]), 'A-01');
    });

    test('continues the latest block, keeping zero-padding', () {
      expect(
        suggestUnitCode(['A-01', 'A-02', 'B-01', 'C-01', 'C-02']),
        'C-03',
      );
    });

    test('single block increments', () {
      expect(suggestUnitCode(['A-01', 'A-02', 'A-03']), 'A-04');
    });

    test('skips a code that is already taken', () {
      // Next would be A-03, but it exists out of order — jump past it.
      expect(suggestUnitCode(['A-01', 'A-02', 'A-04', 'A-03']), 'A-05');
    });

    test('rolls width when the number grows past the padding', () {
      expect(suggestUnitCode(['A-09']), 'A-10');
    });

    test('handles plain numeric codes', () {
      expect(suggestUnitCode(['1', '2', '3']), '4');
    });

    test('handles a custom prefix with a separator', () {
      expect(suggestUnitCode(['Shop-1', 'Shop-2']), 'Shop-3');
    });

    test('ignores blanks and whitespace', () {
      expect(suggestUnitCode(['A-01', '   ', '']), 'A-02');
    });

    test('falls back to A-01 when no code ends in a number', () {
      expect(suggestUnitCode(['lobby', 'kiosk']), 'A-01');
    });

    test('picks the greatest prefix even if it has fewer units', () {
      expect(
        suggestUnitCode(['A-01', 'A-02', 'A-03', 'Z-01']),
        'Z-02',
      );
    });
  });
}
