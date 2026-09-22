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
                        'Set a PIN',
                        textAlign: TextAlign.center,
                        style: Type.title1.bold.colored(sys.label),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        auth.phone == null
                            ? 'This PIN unlocks Rent Bee on every launch'
                            : 'Verified ${auth.phone}. This PIN unlocks Rent Bee '
                                'on every launch.',
                        textAlign: TextAlign.center,
                        style: Type.subhead.colored(sys.secondaryLabel),
                      ),
                      const SizedBox(height: 24),
                      PinField(
                          controller: _pin, label: 'PIN', autofocus: true),
                      const SizedBox(height: 16),
                      PinField(controller: _confirm, label: 'Confirm PIN'),
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
                        child: const Text('Create PIN'),
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
