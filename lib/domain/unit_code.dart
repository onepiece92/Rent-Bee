/// Suggests the next unit code so the owner doesn't have to invent one when
/// adding a unit.
///
/// Codes in this app look like `A-01`, `B-04`, `C-02` — a prefix followed by a
/// trailing number. The suggestion continues the **latest block**: it takes the
/// greatest existing prefix (e.g. `C-`), finds the highest number in it, and
/// returns the next number, keeping the same zero-padding (`C-02` → `C-03`).
///
/// Falls back to `A-01` when there are no units, or no codes end in a number.
/// The result is always guaranteed unique against [existing]; on a collision it
/// keeps incrementing.
String suggestUnitCode(Iterable<String> existing) {
  final codes =
      existing.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  final taken = codes.toSet();

  // Split a code into its leading prefix and trailing digits.
  final re = RegExp(r'^(.*?)(\d+)$');

  // Per prefix: the highest number seen and the widest zero-padding.
  final byPrefix = <String, ({int maxNum, int width})>{};
  for (final c in codes) {
    final m = re.firstMatch(c);
    if (m == null) continue; // no trailing number — can't extend this one
    final prefix = m.group(1)!;
    final digits = m.group(2)!;
    final n = int.parse(digits);
    final cur = byPrefix[prefix];
    byPrefix[prefix] = (
      maxNum: cur == null ? n : (n > cur.maxNum ? n : cur.maxNum),
      width: cur == null
          ? digits.length
          : (digits.length > cur.width ? digits.length : cur.width),
    );
  }

  if (byPrefix.isEmpty) return _firstFree('A-', 2, 1, taken);

  // Continue the latest block: the greatest prefix, e.g. C- over A-/B-.
  final prefix = (byPrefix.keys.toList()..sort()).last;
  final info = byPrefix[prefix]!;
  return _firstFree(prefix, info.width, info.maxNum + 1, taken);
}

/// First `prefix + zero-padded n` (n starting at [start]) not already [taken].
String _firstFree(String prefix, int width, int start, Set<String> taken) {
  for (var n = start; n < start + 100000; n++) {
    final candidate = '$prefix${n.toString().padLeft(width, '0')}';
    if (!taken.contains(candidate)) return candidate;
  }
  return '$prefix${start.toString().padLeft(width, '0')}';
}
