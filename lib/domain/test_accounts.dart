/// Store-review test logins: the phone numbers registered in Firebase Auth
/// under "Phone numbers for testing" (fixed OTP, no SMS sent), which App Store
/// and Play reviewers sign in with. Keep this in sync with the console.
///
/// The single source of truth for everything that treats those accounts
/// specially: the OTP quota exemption (`OtpQuotaService`) and the demo-data
/// tool (`AuthProvider.canGenerateDemoData`).
const Set<String> reviewTestNumbers = {
  '+9779800000000', // Play/App Store review test number (fixed OTP in console)
};

/// Whether [phoneE164] is one of the [reviewTestNumbers].
bool isReviewTestNumber(String? phoneE164) =>
    phoneE164 != null && reviewTestNumbers.contains(phoneE164);
