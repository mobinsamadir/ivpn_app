import 'package:flutter/material.dart';
import 'scale_on_tap.dart';

class AdExplanationDialog extends StatefulWidget {
  final Future<bool> Function() onAdView;

  const AdExplanationDialog({super.key, required this.onAdView});

  @override
  State<AdExplanationDialog> createState() => _AdExplanationDialogState();
}

class _AdExplanationDialogState extends State<AdExplanationDialog> {
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);

  Future<void> _handleViewAd() async {
    _isLoadingNotifier.value = true;
    try {
      final result = await widget.onAdView();
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) {
        _isLoadingNotifier.value = false;
      }
    }
  }

  @override
  void dispose() {
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        'Add 1 Hour Time',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'To keep the service free, please engage with our sponsor.\n\n'
        '1. Click "View Ad"\n'
        '2. Wait 5 seconds\n'
        '3. Close the ad and claim your reward.',
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: _isLoadingNotifier,
          builder: (context, isLoading, child) {
            return ScaleOnTap(
              onTap: isLoading ? null : () => Navigator.pop(context, false),
              child: IgnorePointer(
                child: TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
              ),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _isLoadingNotifier,
          builder: (context, isLoading, child) {
            return isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ScaleOnTap(
                    onTap: _handleViewAd,
                    child: IgnorePointer(
                      child: ElevatedButton(
                        onPressed: _handleViewAd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: const Text(
                          'View Ad',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  );
          },
        ),
      ],
    );
  }
}
