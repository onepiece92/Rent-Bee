import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/auth_provider.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/pin_field.dart';

/// Returning-user unlock. The PIN was set once during onboarding (after phone
/// OTP verification); this screen runs fully offline. First-run PIN creation
/// lives in [SetPinScreen].
///
/// Wrong PINs are limited ([AuthProvider.freeAttempts], then growing
/// timeouts shown as a countdown), and "Forgot PIN?" resets the PIN by
/// verifying the recorded phone number again.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  /// Ticks once a second while the lock screen is timed out, to count down.
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _watchLockout(context.read<AuthProvider>());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _pin.dispose();
    super.dispose();
  }

  void _watchLockout(AuthProvider auth) {
    if (auth.lockoutRemaining <= Duration.zero || _countdown != null) return;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (auth.lockoutRemaining <= Duration.zero) {
        t.cancel();
        _countdown = null;
      }
      if (mounted) setState(() {});
    });
  }

  static String _clock(Duration d) {
    // Round up: "0:00" must never be shown while input is still refused.
    final s = (d.inMilliseconds / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _forgotPin(AuthProvider auth) async {
    final ok = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Reset your PIN?',
        content: Text(
          'We will text a code to ${auth.phone} to confirm it is you, then '
          'you can choose a new PIN. Your units and payments are not '
          'changed.',
          textAlign: TextAlign.center,
        ),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction('Continue',
              primary: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) auth.startPinReset(); // go_router moves to verification
  }

  Future<void> _submit(AuthProvider auth) async {
    if (auth.lockoutRemaining > Duration.zero) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    final pin = _pin.text.trim();
    if (pin.length != 4) {
      setState(() {
        _error = 'PIN must be 4 digits';
        _busy = false;
      });
      return;
    }
    try {
      final ok = await auth.unlock(pin);
      if (!ok && mounted) {
        final left = AuthProvider.freeAttempts - auth.failedAttempts;
        _pin.clear();
        setState(() {
          // Once timed out, the countdown below says everything.
          _error = auth.lockoutRemaining > Duration.zero
              ? null
              : left > 0 && left <= 2
                  ? 'Incorrect PIN · $left ${left == 1 ? 'try' : 'tries'} left'
                  : 'Incorrect PIN';
          _busy = false;
        });
        _watchLockout(auth);
      }
      // On success, go_router redirects on the auth change and disposes this
      // screen — leaving _busy true is fine since the button is gone.
    } catch (_) {
      // PIN derivation runs in an isolate; if it fails, re-enable the button
      // and surface an error instead of leaving it spinning forever.
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final auth = context.watch<AuthProvider>();
    final wait = auth.lockoutRemaining;
    final lockedOut = wait > Duration.zero;

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
                        'Enter your PIN to continue',
                        textAlign: TextAlign.center,
                        style: Type.subhead.colored(sys.secondaryLabel),
                      ),
                      const SizedBox(height: 24),
                      PinField(
                        controller: _pin,
                        label: 'PIN',
                        autofocus: true,
                        onSubmitted:
                            _busy || lockedOut ? null : () => _submit(auth),
                      ),
                      if (lockedOut) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Too many wrong PINs. Try again in ${_clock(wait)}.',
                          textAlign: TextAlign.center,
                          style: Type.footnote.colored(sys.redText).tabular,
                        ),
                      ] else if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: Type.footnote.colored(sys.redText)),
                      ],
                      const SizedBox(height: 24),
                      // Stays a FilledButton: the theme renders it as the
                      // prominent capsule, and the widget tests find it by type.
                      FilledButton(
                        onPressed:
                            _busy || lockedOut ? null : () => _submit(auth),
                        child: const Text('Unlock'),
                      ),
                      if (auth.canResetPin) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: AppButton(
                            kind: ButtonKind.plain,
                            label: 'Forgot PIN?',
                            onTap: () => _forgotPin(auth),
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
