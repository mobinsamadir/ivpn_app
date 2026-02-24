import 'dart:async';
import 'package:flutter/material.dart';
import 'universal_ad_widget.dart';

class FullScreenAdDialog extends StatefulWidget {
  final String unitId;

  const FullScreenAdDialog({
    super.key,
    this.unitId = 'reward_ad',
  });

  @override
  State<FullScreenAdDialog> createState() => _FullScreenAdDialogState();
}

class _FullScreenAdDialogState extends State<FullScreenAdDialog> {
  int _timeLeft = 15; // Strict 15s countdown
  Timer? _timer;
  bool _canClose = false;

  @override
  void initState() {
    super.initState();
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
    // PopScope prevents Back Button to enforce "The Wall" until dismissed
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black, // Force solid background
        body: Stack(
          children: [
            // Main Content Layer
            SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Premium Connection',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        // Timer Badge
                        if (!_canClose)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer, color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  '${_timeLeft}s',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Ad Content
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFF121212), // Inner background just in case
                      child: Center(
                        child: UniversalAdWidget(slot: widget.unitId),
                      ),
                    ),
                  ),

                  // Footer Status
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      border: Border(top: BorderSide(color: Color(0xFF333333))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _canClose
                              ? "Thank you! You can now close this ad."
                              : "Your premium connection is ready in ${_timeLeft}s...",
                          style: TextStyle(
                            color: _canClose ? Colors.greenAccent : Colors.grey[400],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Visual Indicator
                        if (!_canClose)
                          const SizedBox(
                            width: double.infinity,
                            height: 4,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.black,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Escapability Layer: Close Button (Only appears after timer)
            if (_canClose)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.hardEdge,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        tooltip: 'Close & Claim Reward',
                        onPressed: () {
                          // Success!
                          Navigator.of(context).pop(true);
                        },
                      ),
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
