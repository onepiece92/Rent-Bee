import 'package:intl/intl.dart';

/// The ledger's active currency. Global for the whole app (Rent Bee is
/// single-owner — one landlord's whole ledger), not per-unit: aggregating
/// across units already assumes one currency (see `periodSummary`/`summary`
/// in ledger_repository.dart), and mixing currencies per unit would make
/// those sums meaningless without a conversion step this app doesn't have.
enum Currency {
  npr,
  usd;

  /// The prefix `Money.format` renders before the grouped digits.
  String get symbol => switch (this) {
        Currency.npr => 'Rs ',
        Currency.usd => r'$',
      };
}

/// Money is stored and passed as whole integers — never floats — in
/// whichever [Currency] the ledger is set to. Display `Rs 1,80,000`
/// (en-IN grouping) for NPR, `$1,234,567` (en-US grouping) for USD.
class Money {
  static final NumberFormat _enIn = NumberFormat.decimalPattern('en_IN');
  static final NumberFormat _enUs = NumberFormat.decimalPattern('en_US');

  static NumberFormat _formatterFor(Currency currency) => switch (currency) {
        Currency.npr => _enIn,
        Currency.usd => _enUs,
      };

  /// Formats an integer amount with [currency]'s symbol and digit grouping.
  static String format(int amount, Currency currency) =>
      '${currency.symbol}${_formatterFor(currency).format(amount)}';

  /// Grouping only, without the currency symbol.
  static String grouped(int amount, Currency currency) =>
      _formatterFor(currency).format(amount);
}
