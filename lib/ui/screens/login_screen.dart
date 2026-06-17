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
    final auth = context.watch<AuthProvider>();

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
                      const Icon(Icons.storefront_rounded,
                          color: Brand.orange, size: 44),
                      const SizedBox(height: 14),
                      Text(
                        'Rent Bee',
                        textAlign: TextAlign.center,
                        style: display(fontSize: 30, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your PIN to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Brand.muted),
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
                        onPressed: _busy ? null : () => _submit(auth),
                        child: const Text('Unlock',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
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
