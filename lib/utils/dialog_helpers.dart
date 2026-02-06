// lib/utils/dialog_helpers.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/home_provider.dart';

void showAddServerDialog(BuildContext context) {
  final TextEditingController controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Add Configs or Subscription"),
      content: TextField(
        controller: controller,
        maxLines: 5,
        minLines: 1,
        decoration: const InputDecoration(
          hintText: "Paste config(s) or subscription link...",
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final userInput = controller.text.trim();
            if (userInput.isNotEmpty) {
              // **THE FIX**: Calling the new, correct method name
              context.read<HomeProvider>().addServersFromUserInput(userInput);
              Navigator.of(ctx).pop();
            }
          },
          child: const Text("Add"),
        ),
      ],
    ),
  );
}

void showCleanupDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cleanup Server List'),
      content: const Text('This will permanently remove servers.'),
      actions: <Widget>[
        TextButton(
          child: const Text('Remove Offline'),
          onPressed: () {
            context.read<HomeProvider>().cleanupServers(removeSlow: false);
            Navigator.of(ctx).pop();
          },
        ),
        TextButton(
          child: const Text('Remove Slow & Offline'),
          onPressed: () {
            context.read<HomeProvider>().cleanupServers(removeSlow: true);
            Navigator.of(ctx).pop();
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
