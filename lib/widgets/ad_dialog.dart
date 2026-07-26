import 'dart:async';
import 'package:flutter/material.dart';
import 'scale_on_tap.dart';
import '../services/ad_manager_service.dart';
import 'universal_ad_widget.dart';

class AdDialog extends StatefulWidget {
  final String unitId;

  const AdDialog({
    super.key,
    this.unitId = 'reward_ad', // Changed default to match new system
  });

  @override
  State<AdDialog> createState() => _AdDialogState();
}

class _AdDialogState extends State<AdDialog> {
  final ValueNotifier<int> _timeLeftNotifier = ValueNotifier<int>(10);
  final ValueNotifier<bool> _canCloseNotifier = ValueNotifier<bool>(false);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    final ad = AdManagerService().getAdUnit(widget.unitId);
    int initialTime = ad?.timerSeconds ?? 10;
    // Enforce a minimum safety of 3 seconds if enabled, unless explicitly 0
    if (initialTime > 0 && initialTime < 3) {
      initialTime = 3;
    }
    _timeLeftNotifier.value = initialTime;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeftNotifier.value > 0) {
        if (mounted) {
          _timeLeftNotifier.value--;
        }
      } else {
        _timer?.cancel();
        if (mounted) {
          _canCloseNotifier.value = true;
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeLeftNotifier.dispose();
    _canCloseNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sponsored Content',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _canCloseNotifier,
                  builder: (context, canClose, child) {
                    if (canClose) {
                      return IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.of(context).pop(true),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // WebView Content (Using Reusable UniversalAdWidget)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.transparent,
                  child: UniversalAdWidget(slot: widget.unitId),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ValueListenableBuilder<bool>(
                valueListenable: _canCloseNotifier,
                builder: (context, canClose, child) {
                  return ValueListenableBuilder<int>(
                    valueListenable: _timeLeftNotifier,
                    builder: (context, timeLeft, child) {
                      return ScaleOnTap(
                        onTap: canClose ? () => Navigator.of(context).pop(true) : null,
                        child: IgnorePointer(
                          child: ElevatedButton(
                            onPressed: canClose ? () {} : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  canClose ? Colors.green : Colors.grey[800],
                              disabledBackgroundColor: Colors.grey[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              canClose
                                  ? 'Close & Connect'
                                  : 'Please wait (${timeLeft}s)...',
                              style: TextStyle(
                                color: canClose ? Colors.white : Colors.white54,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
