import 'package:intl/intl.dart';

/// Money is stored and passed as whole NPR integers — never floats.
/// Display `Rs 1,80,000` (en-IN grouping).
class Money {
  static final NumberFormat _enIn = NumberFormat.decimalPattern('en_IN');

  /// Formats an integer NPR amount with the `Rs ` prefix and en-IN grouping.
  static String format(int npr) => 'Rs ${_enIn.format(npr)}';

  /// Grouping only, without the `Rs ` prefix.
  static String grouped(int npr) => _enIn.format(npr);
}
