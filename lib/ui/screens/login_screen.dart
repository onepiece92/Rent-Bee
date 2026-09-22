import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/auth_provider.dart';
import '../widgets/glass.dart';
import '../widgets/pin_field.dart';

/// Returning-user unlock. The PIN was set once during onboarding (after phone
/// OTP verification); this screen runs fully offline. First-run PIN creation
/// lives in [SetPinScreen].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
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
        setState(() {
          _error = 'Incorrect PIN';
          _busy = false;
        });
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
                        onSubmitted: _busy ? null : () => _submit(auth),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: Type.footnote.colored(sys.redText)),
                      ],
                      const SizedBox(height: 24),
                      // Stays a FilledButton: the theme renders it as the
                      // prominent capsule, and the widget tests find it by type.
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(auth),
                        child: const Text('Unlock'),
                      ),
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
