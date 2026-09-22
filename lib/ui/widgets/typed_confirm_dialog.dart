import 'package:flutter/material.dart';

import 'glass_dialog.dart';

/// A confirmation for an irreversible, high-impact action: the destructive
/// button stays disabled until the person types [word] (case-insensitive,
/// surrounding whitespace ignored). Resolves `true` on confirm, `false`/null
/// on cancel — a drop-in for a plain confirm dialog.
///
/// ```dart
/// final ok = await showGlassDialog<bool>(
///   context, (_) => const TypedConfirmDialog(
///     title: 'Erase all data?', message: '…', word: 'ERASE',
///     confirmLabel: 'Erase'));
/// ```
class TypedConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String word;
  final String confirmLabel;

  const TypedConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.word,
    required this.confirmLabel,
  });

  @override
  State<TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<TypedConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_check);
  }

  void _check() {
    final m = _ctrl.text.trim().toUpperCase() == widget.word.toUpperCase();
    if (m != _matches) setState(() => _matches = m);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.pop(context, true);

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 14),
          Text('Type ${widget.word} to confirm.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: widget.word, isDense: true),
            onSubmitted: (_) {
              if (_matches) _confirm();
            },
          ),
        ],
      ),
      actions: [
        GlassDialogAction('Cancel',
            onPressed: () => Navigator.pop(context, false)),
        GlassDialogAction(
          widget.confirmLabel,
          destructive: true,
          onPressed: _matches ? _confirm : null, // disabled until typed
        ),
      ],
    );
  }
}
