import 'package:flutter/material.dart';

import '../widgets/glass.dart';

/// Secondary action inside the unit sheets: a compact tinted capsule with an
/// icon + label (kit `tinted`). Sits at its natural width next to a heading,
/// or at full width when [expand] is set (callers that used to wrap it in an
/// `Expanded`).
class SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expand;
  const SecondaryButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.expand = false});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: icon,
      onTap: onTap,
      kind: ButtonKind.tinted,
      compact: true,
      expand: expand,
    );
  }
}
