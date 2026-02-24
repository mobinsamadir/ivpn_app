import 'package:flutter/material.dart';

class AdExplanationDialog extends StatelessWidget {
  const AdExplanationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Add 1 Hour Time', style: TextStyle(color: Colors.white)),
      content: const Text(
        'To keep the service free, please engage with our sponsor.\n\n'
        '1. Click "View Ad"\n'
        '2. Wait 5 seconds\n'
        '3. Close the ad and claim your reward.',
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: const Text('View Ad', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
