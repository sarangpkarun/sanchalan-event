import 'package:flutter/material.dart';

/// Asks for an invite code. Returns the trimmed code, or null if cancelled.
Future<String?> showJoinDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Join with code'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Invite code', hintText: 'e.g. K7M2PQ4X'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: const Text('Join'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
