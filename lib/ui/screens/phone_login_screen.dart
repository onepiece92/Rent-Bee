import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/account_auth_service.dart';
import '../../data/account_deletion.dart';
import '../../data/otp_quota_service.dart';
import '../../data/phone_auth_service.dart';
import '../../domain/email.dart';
import '../../domain/phone.dart';
import '../../state/auth_provider.dart';
import '../../state/ledger_provider.dart';
import '../../state/sync_status.dart';
import '../widgets/glass.dart';

/// Onboarding step 1: sign the owner in.
///
/// The owner picks a method — Google, Apple, a 6-digit code sent by email, or
/// (the original method) an SMS code to a phone number. On success the
/// identity (email or phone) + Firebase uid are recorded
/// ([AuthProvider.recordPhoneVerification]) and go_router advances to the
/// set-PIN screen.
///
/// Everyone who signs in with the same email reaches the same ledger, so a
/// shared Google account or a shared inbox is how several people use one
/// account.
///
/// The same screen resets a forgotten PIN ([AuthProvider.resettingPin]): the
/// identity is then fixed to the one this device was set up with, and signing
/// in as it again clears the PIN instead of recording a new identity.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

enum _Step { choose, phone, otp, email, emailCode }

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _service = PhoneAuthService();
  final _accounts = AccountAuthService();
  final _phone = TextEditingController(text: '+977');
  final _otp = TextEditingController();
  final _email = TextEditingController();

  _Step _step = _Step.choose;
  String? _verificationId;
  String? _phoneE164;
  String? _emailAddress;
  String? _error;
  bool _busy = false;

  /// The account is being deleted (after a successful re-verification).
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.reverifying) {
      // Only the recorded identity can reset the PIN or delete the account,
      // by its own method.
      if (auth.signedInWithEmail) {
        _email.text = auth.phone ?? '';
      } else {
        _phone.text = auth.phone ?? '';
        _step = _Step.phone;
      }
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _email.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _busy = false;
    });
  }

  void _go(_Step step) => setState(() {
        _step = step;
        _otp.clear();
        _error = null;
        _busy = false;
      });

  // ---- phone (SMS) ---------------------------------------------------------

  Future<void> _sendCode(AuthProvider auth) async {
    // A PIN reset verifies the recorded number, whatever the field holds.
    final e164 =
        auth.reverifying ? auth.phone ?? '' : normalizePhone(_phone.text);
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
      // Enforce the global daily OTP cap before spending an SMS.
      final quota = await OtpQuotaService().tryReserve(e164);
      if (!quota.allowed) {
        _fail(_limitReachedMessage(quota.resetAt));
        return;
      }
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
        onAutoVerified: (user) => _recordAndAdvance(
            auth, (uid: user.uid, identity: e164)),
        onError: _fail,
      );
    } catch (e) {
      _fail('$e');
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
      await _recordAndAdvance(auth,
          (uid: user.uid, identity: _phoneE164 ?? user.phoneNumber ?? ''));
    } on FirebaseAuthException catch (e) {
      _fail(e.message ?? 'Incorrect code. Try again.');
    } catch (e) {
      // Anything non-Firebase (e.g. a prefs write in _recordAndAdvance) must
      // still clear _busy, or the button spins forever.
      _fail('Verification failed: $e');
    }
  }

  /// Message shown when the global daily OTP cap is exhausted, telling the user
  /// roughly how long until verification is available again.
  String _limitReachedMessage(DateTime? resetAt) {
    if (resetAt == null) {
      return 'Verification is temporarily unavailable. Please try again later.';
    }
    final left = resetAt.difference(DateTime.now());
    if (left.isNegative) return 'Please try again now.';
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    final wait = hours > 0 ? '$hours h $minutes min' : '$minutes min';
    return 'Daily verification limit reached. Please try again in $wait.';
  }

  // ---- Google / Apple / emailed code --------------------------------------

  /// Runs one of the email-identity sign-ins and records the result.
  Future<void> _signIn(
      AuthProvider auth, Future<SignedInAccount> Function() run) async {
    // Only an Apple sign-in made now may be revoked by a deletion.
    AccountAuthService.lastAppleAuthorizationCode = null;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await _recordAndAdvance(auth, await run());
    } on AccountAuthException catch (e) {
      if (e.cancelled) {
        if (mounted) setState(() => _busy = false);
      } else {
        _fail(e.message);
      }
    } catch (e) {
      _fail('Sign-in failed: $e');
    }
  }

  Future<void> _sendEmailCode(AuthProvider auth) async {
    final address =
        normalizeEmail(auth.reverifying ? auth.phone ?? '' : _email.text);
    final err = emailError(address);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
      _emailAddress = address;
    });
    try {
      await _accounts.requestEmailCode(address);
      if (!mounted) return;
      _go(_Step.emailCode);
    } on AccountAuthException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not send the code: $e');
    }
  }

  Future<void> _confirmEmailCode(AuthProvider auth) async {
    final code = _otp.text.trim();
    final address = _emailAddress;
    if (address == null) return;
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    await _signIn(auth, () => _accounts.confirmEmailCode(address, code));
  }

  Future<void> _recordAndAdvance(
      AuthProvider auth, SignedInAccount account) async {
    if (auth.deletingAccount) {
      if (!auth.isOwnIdentity(account.identity)) {
        _fail(auth.signedInWithEmail
            ? 'That is not the account this device is signed in to '
                '(${auth.phone}).'
            : 'That is not the number this device is signed in with.');
        return;
      }
      await _deleteAccount(auth, account.uid);
      return;
    }
    if (auth.resettingPin) {
      final ok = await auth.completePinReset(account.identity, account.uid);
      if (!ok) {
        _fail(auth.signedInWithEmail
            ? 'That is not the account this device was set up with '
                '(${auth.phone}).'
            : 'That is not the number this device was set up with.');
      }
      return; // on success go_router advances to the set-PIN screen
    }
    await auth.recordPhoneVerification(account.identity, account.uid);
    // go_router redirect advances to the set-PIN screen on auth change.
  }

  /// The owner has just signed in again as themselves: delete the cloud
  /// ledger, the sign-in account and the ledger on this device, then return
  /// to first-run sign-in.
  Future<void> _deleteAccount(AuthProvider auth, String uid) async {
    final ledger = context.read<LedgerProvider>();
    final status = context.read<SyncStatusController>();
    final appleCode = AccountAuthService.lastAppleAuthorizationCode;
    AccountAuthService.lastAppleAuthorizationCode = null;
    if (mounted) setState(() => _deleting = true);
    try {
      await AccountDeletion(
        repo: ledger.repo,
        firestore: FirebaseFirestore.instance,
        deleteUser: () async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null || user.uid != uid) {
            throw StateError('Not signed in to the account being deleted.');
          }
          await user.delete();
        },
        revokeApple: appleCode == null
            ? null
            : () => _accounts.revokeAppleToken(appleCode),
      ).run(uid);
      status.setOff();
      await ledger.refresh(showLoading: true);
      await auth.finishAccountDeletion(); // go_router returns to sign-in
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _deleting = false);
      _fail(e.code == 'requires-recent-login'
          ? 'Please sign in again to confirm, then retry.'
          : 'Could not delete the account (${e.code}). Please try again.');
    } catch (e) {
      if (mounted) setState(() => _deleting = false);
      _fail('Could not delete the account: $e');
    }
  }

  // ---- build ---------------------------------------------------------------

  String _subtitle(bool resetting, AuthProvider auth) => switch (_step) {
        _Step.otp => 'Enter the code sent to ${_phoneE164 ?? ''}',
        _Step.emailCode => 'Enter the code sent to ${_emailAddress ?? ''}',
        _Step.phone when auth.deletingAccount =>
          'To delete your account, confirm it is you: verify your number by '
              'SMS.',
        _Step.phone => resetting
            ? 'Forgot your PIN? Verify your number by SMS to set a new one. '
                'Your ledger stays as it is.'
            : 'Verify your phone number to get started',
        _Step.email => 'We will email you a 6-digit code',
        _Step.choose when auth.deletingAccount =>
          'To delete your account, confirm it is you: sign in as '
              '${auth.phone}.',
        _Step.choose => resetting
            ? 'Forgot your PIN? Sign in again as ${auth.phone} to set a new '
                'one. Your ledger stays as it is.'
            : 'Sign in to get started',
      };

  List<Widget> _chooser(AuthProvider auth, bool resetting) => [
        if (AccountAuthService.googleAvailable) ...[
          AppButton(
            kind: ButtonKind.prominent,
            expand: true,
            busy: _busy,
            icon: Icons.account_circle_outlined,
            label: 'Continue with Google',
            onTap: _busy
                ? null
                : () => _signIn(auth, _accounts.signInWithGoogle),
          ),
          const SizedBox(height: 10),
        ],
        if (AccountAuthService.appleAvailable) ...[
          AppButton(
            kind: ButtonKind.gray,
            expand: true,
            icon: Icons.apple,
            label: 'Continue with Apple',
            onTap: _busy
                ? null
                : () => _signIn(auth, _accounts.signInWithApple),
          ),
          const SizedBox(height: 10),
        ],
        if (AccountAuthService.emailCodeReady)
          AppButton(
            kind: ButtonKind.gray,
            expand: true,
            icon: Icons.mail_outline_rounded,
            label: resetting ? 'Email me a code' : 'Continue with email',
            onTap: _busy
                ? null
                : () => resetting ? _sendEmailCode(auth) : _go(_Step.email),
          ),
        if (!resetting) ...[
          const SizedBox(height: 4),
          Center(
            child: AppButton(
              kind: ButtonKind.plain,
              label: 'Use a phone number instead',
              onTap: _busy ? null : () => _go(_Step.phone),
            ),
          ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final auth = context.watch<AuthProvider>();
    final resetting = auth.reverifying;
    final step = _step;
    final isCode = step == _Step.otp || step == _Step.emailCode;

    final (String label, VoidCallback action)? primary = switch (step) {
      _Step.choose => null,
      _Step.phone => ('Send code', () => _sendCode(auth)),
      _Step.otp => ('Verify', () => _confirmCode(auth)),
      _Step.email => ('Send code', () => _sendEmailCode(auth)),
      _Step.emailCode => ('Verify', () => _confirmEmailCode(auth)),
    };

    // Where "back" leads from this step; null when there is nowhere to go
    // (the chooser itself, or a reset pinned to the recorded phone number).
    final (String label, VoidCallback action)? back = switch (step) {
      _Step.choose => null,
      _Step.phone =>
        resetting ? null : ('Other ways to sign in', () => _go(_Step.choose)),
      _Step.otp =>
        resetting ? null : ('Change number', () => _go(_Step.phone)),
      _Step.email => ('Other ways to sign in', () => _go(_Step.choose)),
      _Step.emailCode => resetting
          ? ('Other ways to sign in', () => _go(_Step.choose))
          : ('Change email', () => _go(_Step.email)),
    };

    return Scaffold(
      body: PageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sys.gutter),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GroupedCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AppIcon(),
                      const SizedBox(height: 16),
                      Text(
                        'Rent Bee',
                        textAlign: TextAlign.center,
                        style: Type.title1.bold.colored(sys.label),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(resetting, auth),
                        textAlign: TextAlign.center,
                        style: Type.subhead.colored(sys.secondaryLabel),
                      ),
                      const SizedBox(height: 24),
                      if (step == _Step.choose) ..._chooser(auth, resetting),
                      if (step == _Step.phone)
                        _Field(
                          controller: _phone,
                          label: 'Phone number',
                          hint: '+9779801234501',
                          keyboardType: TextInputType.phone,
                          autofocus: !resetting,
                          readOnly: resetting, // only the recorded number
                          formatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                          ],
                          onSubmitted: _busy ? null : primary?.$2,
                        ),
                      if (step == _Step.email)
                        _Field(
                          controller: _email,
                          label: 'Email address',
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          autofocus: true,
                          formatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          onSubmitted: _busy ? null : primary?.$2,
                        ),
                      if (isCode)
                        _Field(
                          controller: _otp,
                          label: step == _Step.otp ? 'SMS code' : 'Email code',
                          hint: '123456',
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          maxLength: 6,
                          spaced: true, // a code reads digit by digit
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          onSubmitted: _busy ? null : primary?.$2,
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: Type.footnote.colored(sys.redText)),
                      ],
                      if (primary != null) ...[
                        const SizedBox(height: 24),
                        AppButton(
                          kind: ButtonKind.prominent,
                          expand: true,
                          busy: _busy,
                          label: primary.$1,
                          onTap: _busy ? null : primary.$2,
                        ),
                      ],
                      if (back != null && !_busy) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: AppButton(
                            kind: ButtonKind.plain,
                            label: back.$1,
                            onTap: back.$2,
                          ),
                        ),
                      ],
                      if (_deleting) ...[
                        const SizedBox(height: 16),
                        Text('Deleting your account…',
                            textAlign: TextAlign.center,
                            style: Type.subhead.colored(sys.secondaryLabel)),
                      ],
                      if (resetting && !_busy && !_deleting) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: AppButton(
                            kind: ButtonKind.plain,
                            label: auth.deletingAccount
                                ? 'Cancel, keep my account'
                                : 'Back to PIN',
                            onTap: auth.deletingAccount
                                ? auth.cancelAccountDeletion
                                : auth.cancelPinReset,
                          ),
                        ),
                      ],
                      // Debug-only shortcut to skip sign-in + PIN while
                      // testing. Never compiled into release builds.
                      if (kDebugMode &&
                          step == _Step.choose &&
                          !_busy &&
                          !resetting) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: AppButton(
                            kind: ButtonKind.plain,
                            label: 'Continue as guest (debug)',
                            onTap: () => auth.enterGuestMode(),
                          ),
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

/// The app icon at 72 pt with 16 pt corners, centred above the title.
class _AppIcon extends StatelessWidget {
  const _AppIcon();

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/icon/rent_bee.png',
          width: 72,
          height: 72,
          // Source is 512² — decode to ~2x the display size, not full.
          cacheWidth: 144,
          cacheHeight: 144,
          fit: BoxFit.cover,
          // The title text below carries the name.
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) =>
              Icon(Icons.apartment_rounded, size: 48, color: sys.tint),
        ),
      ),
    );
  }
}

/// A phone / code field on the theme's input decoration (tertiarySystemFill,
/// no border, 14 pt radius) with tabular digits.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType keyboardType;
  final bool autofocus;
  final int? maxLength;
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
    this.onSubmitted,
    this.spaced = false,
    this.readOnly = false,
  });

  final bool readOnly;

  /// Wide tracking for one-time codes, so each digit is checkable at a glance.
  final bool spaced;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      maxLength: maxLength,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      style: spaced ? Type.body.tabular.copyWith(letterSpacing: 8) : Type.body.tabular,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    );
  }
}
