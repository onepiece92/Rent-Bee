import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// Shared 4-digit PIN entry field, used by both the unlock screen and the
/// onboarding set-PIN screen. Obscured, numeric, capped at 4 digits.
///
/// Reads like the iOS passcode row: four dots that fill in the tint as digits
/// are typed. The digits themselves go into an invisible [TextField] laid
/// under the dots — it still owns the controller, focus, the number keyboard,
/// the length cap and `onSubmitted`, so a tap on the row brings the keyboard
/// up and tests can type into it like any other field.
class PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  /// Number of digits (and dots).
  static const int length = 4;

  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Type.footnote.colored(sys.secondaryLabel),
        ),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            // The real field: painted invisible but present in the tree, so
            // it keeps its tap surface, focus, keyboard and semantics.
            Opacity(
              opacity: 0,
              alwaysIncludeSemantics: true,
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: length,
                showCursor: false,
                enableInteractiveSelection: false,
                onSubmitted:
                    onSubmitted == null ? null : (_) => onSubmitted!(),
                style: Type.body,
                decoration: InputDecoration(labelText: label, counterText: ''),
              ),
            ),
            // Decorative: taps fall through to the field, VoiceOver reads
            // the field.
            IgnorePointer(
              child: ExcludeSemantics(child: _Dots(controller: controller)),
            ),
          ],
        ),
      ],
    );
  }
}

/// One dot per digit: the tint once typed, systemFill while empty.
class _Dots extends StatelessWidget {
  final TextEditingController controller;
  const _Dots({required this.controller});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final filled = value.text.length;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < PinField.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: AnimatedContainer(
                  duration: Motion.duration(context, Motion.quick),
                  curve: Motion.fade,
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: i < filled ? sys.tint : sys.fill,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
