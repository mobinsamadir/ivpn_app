import 'package:flutter/material.dart';

class AdExplanationDialog extends StatefulWidget {
  final Future<bool> Function() onAdView;

  const AdExplanationDialog({
    super.key,
    required this.onAdView,
  });

  @override
  State<AdExplanationDialog> createState() => _AdExplanationDialogState();
}

class _AdExplanationDialogState extends State<AdExplanationDialog> {
  bool _isLoading = false;

  Future<void> _handleViewAd() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.onAdView();
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, false);
      }
    }
  }

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
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: _handleViewAd,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: const Text('View Ad', style: TextStyle(color: Colors.white)),
              ),
      ],
    );
  }
}
