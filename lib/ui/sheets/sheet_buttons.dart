import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Ghost button for secondary actions inside the unit sheets — an icon + label
/// on a glass pill. Used at full width (inside an `Expanded`) and at its natural
/// min width next to a heading, so it carries its own horizontal padding.
class SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const SecondaryButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Brand.glassBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Brand.orangeSoft),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Brand.orangeSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
