/// Lower-cases and trims an email address — the form an account is recorded
/// and compared under, so `Owner@Gmail.com ` and `owner@gmail.com` are one
/// identity.
String normalizeEmail(String raw) => raw.trim().toLowerCase();

/// Returns an error string for a sign-in email, or null when acceptable.
/// Deliberately loose (one `@`, a dot in the domain, no spaces): the code that
/// is emailed is the real check that the address exists.
String? emailError(String raw) {
  final v = normalizeEmail(raw);
  if (v.isEmpty) return 'Enter your email address';
  if (v.length > 254 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s.]+$').hasMatch(v)) {
    return 'Enter a valid email address';
  }
  return null;
}

/// Whether a recorded account identity is an email (as opposed to an E.164
/// phone number from the SMS sign-in).
bool isEmailIdentity(String? identity) =>
    identity != null && identity.contains('@');
