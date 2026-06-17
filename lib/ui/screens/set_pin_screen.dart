import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/auth_provider.dart';
import '../widgets/glass.dart';
import '../widgets/pin_field.dart';

/// Onboarding step 2: create the local PIN, after the phone has been verified.
/// Setting the PIN unlocks the app; every later launch uses [LoginScreen].
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
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
    if (pin != _confirm.text.trim()) {
      setState(() {
        _error = 'PINs do not match';
        _busy = false;
      });
      return;
    }
    try {
      await auth.setPin(pin); // unlocks + notifies; go_router redirects to '/'.
    } catch (_) {
      // PIN derivation runs in an isolate; on failure re-enable the button and
      // show an error rather than leaving the user stuck mid-onboarding.
      if (mounted) {
        setState(() {
          _error = 'Could not save your PIN. Please try again.';
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
                      const Icon(Icons.lock_outline_rounded,
                          color: Brand.orange, size: 44),
                      const SizedBox(height: 14),
                      Text(
                        'Set a PIN',
                        textAlign: TextAlign.center,
                        style: display(fontSize: 28, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        auth.phone == null
                            ? 'This PIN unlocks Rent Bee on every launch'
                            : 'Verified ${auth.phone}. This PIN unlocks Rent Bee '
                                'on every launch.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Brand.muted),
                      ),
                      const SizedBox(height: 24),
                      PinField(
                          controller: _pin, label: 'PIN', autofocus: true),
                      const SizedBox(height: 14),
                      PinField(controller: _confirm, label: 'Confirm PIN'),
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
                        child: const Text('Create PIN',
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
