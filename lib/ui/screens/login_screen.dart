import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/auth_provider.dart';
import '../widgets/glass.dart';

/// Single-owner lock. First run sets a PIN; later runs unlock with it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
    if (!auth.hasPin) {
      if (pin != _confirm.text.trim()) {
        setState(() {
          _error = 'PINs do not match';
          _busy = false;
        });
        return;
      }
      await auth.setPin(pin);
    } else {
      final ok = await auth.unlock(pin);
      if (!ok) {
        setState(() {
          _error = 'Incorrect PIN';
          _busy = false;
        });
        return;
      }
    }
    // Redirect handled by go_router on auth change.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isSetup = !auth.hasPin;

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
                      Text(
                        isSetup
                            ? 'Set a PIN to secure your ledger'
                            : 'Enter your PIN to continue',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Brand.muted),
                      ),
                      const SizedBox(height: 24),
                      _PinField(
                          controller: _pin, label: 'PIN', autofocus: true),
                      if (isSetup) ...[
                        const SizedBox(height: 14),
                        _PinField(
                            controller: _confirm, label: 'Confirm PIN'),
                      ],
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
                        child: Text(isSetup ? 'Create PIN' : 'Unlock',
                            style: const TextStyle(
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

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  const _PinField(
      {required this.controller, required this.label, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 4,
      style: const TextStyle(letterSpacing: 6, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
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
