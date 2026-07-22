import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/phone_auth_service.dart';
import '../../domain/phone.dart';
import '../../state/auth_provider.dart';
import '../widgets/glass.dart';

/// Onboarding step 1: verify the owner's phone number via Firebase OTP.
///
/// Two internal steps live in one screen: enter the phone number → enter the
/// SMS code. On success the verified number + Firebase uid are recorded
/// ([AuthProvider.recordPhoneVerification]) and go_router advances to the
/// set-PIN screen. The field defaults to a `+977` (Nepal) prefix.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

enum _Step { phone, otp }

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _service = PhoneAuthService();
  final _phone = TextEditingController(text: '+977');
  final _otp = TextEditingController();

  _Step _step = _Step.phone;
  String? _verificationId;
  String? _phoneE164;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendCode(AuthProvider auth) async {
    final e164 = normalizePhone(_phone.text);
    final err = phoneError(e164);
    if (err != null || !e164.startsWith('+')) {
      setState(() => _error = err ?? 'Include the country code, e.g. +977…');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
      _phoneE164 = e164;
    });
    try {
      await PhoneAuthService.ensureInitialized();
      await _service.verifyPhoneNumber(
        phoneE164: e164,
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _step = _Step.otp;
            _busy = false;
          });
        },
        onAutoVerified: (user) => _recordAndAdvance(auth, user),
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _error = message;
            _busy = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _confirmCode(AuthProvider auth) async {
    final id = _verificationId;
    final code = _otp.text.trim();
    if (id == null) return;
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await PhoneAuthService.ensureInitialized();
      final user = await _service.confirmOtp(id, code);
      await _recordAndAdvance(auth, user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Incorrect code. Try again.';
        _busy = false;
      });
    } catch (e) {
      // Anything non-Firebase (e.g. a prefs write in _recordAndAdvance) must
      // still clear _busy, or the button spins forever.
      if (!mounted) return;
      setState(() {
        _error = 'Verification failed: $e';
        _busy = false;
      });
    }
  }

  Future<void> _recordAndAdvance(AuthProvider auth, User user) async {
    await auth.recordPhoneVerification(_phoneE164 ?? user.phoneNumber ?? '', user.uid);
    // go_router redirect advances to the set-PIN screen on auth change.
  }

  void _editNumber() {
    setState(() {
      _step = _Step.phone;
      _otp.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOtp = _step == _Step.otp;

    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: GlassPanel(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.smartphone_rounded,
                          color: Brand.orange, size: 44),
                      const SizedBox(height: 14),
                      Text(
                        'Rent Bee',
                        textAlign: TextAlign.center,
                        style: display(fontSize: 30, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isOtp
                            ? 'Enter the code sent to ${_phoneE164 ?? ''}'
                            : 'Verify your phone number to get started',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Brand.muted),
                      ),
                      const SizedBox(height: 24),
                      if (!isOtp)
                        _Field(
                          controller: _phone,
                          label: 'Phone number',
                          hint: '+9779801234501',
                          keyboardType: TextInputType.phone,
                          autofocus: true,
                          formatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                          ],
                          onSubmitted: _busy ? null : () => _sendCode(auth),
                        )
                      else
                        _Field(
                          controller: _otp,
                          label: 'SMS code',
                          hint: '123456',
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          maxLength: 6,
                          letterSpacing: 8,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          onSubmitted: _busy ? null : () => _confirmCode(auth),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(color: Colors.redAccent)),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy
                            ? null
                            : () => isOtp ? _confirmCode(auth) : _sendCode(auth),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(isOtp ? 'Verify' : 'Send code',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      if (isOtp && !_busy) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _editNumber,
                          child: const Text('Change number',
                              style: TextStyle(color: Brand.muted)),
                        ),
                      ],
                      // Debug-only shortcut to skip OTP + PIN while testing
                      // (e.g. on macOS where phone auth uses reCAPTCHA). Never
                      // compiled into release builds.
                      if (kDebugMode && !isOtp && !_busy) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => auth.enterGuestMode(),
                          child: const Text('Continue as guest (debug)',
                              style: TextStyle(color: Brand.muted)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType keyboardType;
  final bool autofocus;
  final int? maxLength;
  final double letterSpacing;
  final List<TextInputFormatter> formatters;
  final VoidCallback? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.keyboardType,
    required this.formatters,
    this.hint,
    this.autofocus = false,
    this.maxLength,
    this.letterSpacing = 1,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      maxLength: maxLength,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      style: TextStyle(letterSpacing: letterSpacing, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Brand.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Brand.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Brand.orange),
        ),
      ),
    );
  }
}
