import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ad_manager_service.dart';
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
  int _timeLeft = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  void _initializeTimer() {
    final ad = AdManagerService().getAdUnit(widget.unitId);
    // Enforce 10s minimum regardless of config, as per "The Wall" requirement
    _timeLeft = (ad?.timerSeconds ?? 10);
    if (_timeLeft < 10) _timeLeft = 10;

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
          // Failsafe: Auto-dismiss on timeout (Success)
          Navigator.of(context).pop(true);
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
    // PopScope prevents Back Button to enforce "The Wall" until dismissed or closed
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Optionally block interaction or show toast
      },
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
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        // Timer Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '${_timeLeft}s',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
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
                      color: const Color(
                          0xFF121212), // Inner background just in case
                      child: Center(
                        child: UniversalAdWidget(slot: widget.unitId),
                      ),
                    ),
                  ),

                  // Footer "The Wall" Action Area
                  // Modified: Now just shows status, no button needed as it auto-dismisses
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
                          "Your premium connection is ready in ${_timeLeft}s...",
                          style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 20),
                        // Visual Indicator that work is happening (or waiting)
                        const SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Colors.blueAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Escapability Layer: Close Button
            // Positioned relative to the safe area
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Material(
                    color: Colors
                        .black54, // Semi-transparent for visibility over white ads
                    shape: const CircleBorder(),
                    clipBehavior: Clip.hardEdge,
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      tooltip: 'Close Ad',
                      onPressed: () {
                        // User explicitly closed it -> No Reward (False)
                        Navigator.of(context).pop(false);
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
