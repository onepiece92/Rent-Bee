/// Strips a phone number down to its digits plus an optional single leading
/// `+`, removing the spaces, dashes, dots and parens that creep in when a
/// number is pasted (e.g. `+977-9801 234 501` → `+9779801234501`).
String normalizePhone(String raw) {
  final trimmed = raw.trim();
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return hasPlus && digits.isNotEmpty ? '+$digits' : digits;
}

/// Validates an optional contact number for the unit form. Returns an error
/// string, or null when acceptable.
///
/// Blank is allowed — phone is optional. Otherwise the normalized number must
/// hold 10–14 digits: a bare 10-digit local mobile up to a `+977`-prefixed
/// international form. This catches fat-finger typos without rejecting the
/// formats owners actually paste.
String? phoneError(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return null;
  final digits = normalizePhone(v).replaceAll('+', '');
  if (digits.length < 10 || digits.length > 14) {
    return 'Enter a valid phone number';
  }
  return null;
}
