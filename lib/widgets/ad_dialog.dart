import 'dart:async';
import 'package:flutter/material.dart';
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
  int _timeLeft = 10;
  bool _canClose = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    final ad = AdManagerService().getAdUnit(widget.unitId);
    _timeLeft = ad?.timerSeconds ?? 10;
    // Enforce a minimum safety of 3 seconds if enabled, unless explicitly 0
    if (_timeLeft > 0 && _timeLeft < 3) {
      _timeLeft = 3;
    }
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        if (mounted) {
          setState(() {
            _timeLeft--;
          });
        }
      } else {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _canClose = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
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
                      fontWeight: FontWeight.bold),
                ),
                if (_canClose)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(true),
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
              child: ElevatedButton(
                onPressed:
                    _canClose ? () => Navigator.of(context).pop(true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canClose ? Colors.green : Colors.grey[800],
                  disabledBackgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _canClose
                      ? 'Close & Connect'
                      : 'Please wait (${_timeLeft}s)...',
                  style: TextStyle(
                    color: _canClose ? Colors.white : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
