import 'dart:async';
import 'package:flutter/material.dart';
import 'universal_ad_widget.dart';
import '../services/ad_manager_service.dart';
import 'scale_on_tap.dart';

class FullScreenAdDialog extends StatefulWidget {
  final String unitId;

  const FullScreenAdDialog({super.key, this.unitId = 'reward_ad'});

  @override
  State<FullScreenAdDialog> createState() => _FullScreenAdDialogState();
}

class _FullScreenAdDialogState extends State<FullScreenAdDialog> {
  final ValueNotifier<int> _timeLeftNotifier =
      ValueNotifier<int>(15); // Strict 15s countdown
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeLeftNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kEnableAds) {
      // Short-circuit: Immediately close and return success when ads are disabled
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop(true);
      });
      return const SizedBox.shrink();
    }
    // PopScope prevents Back Button to enforce "The Wall" until dismissed
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black, // Force solid background
        body: Stack(
          children: [
            // 1. True Fullscreen Ad Layer (100% of Screen)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: UniversalAdWidget(slot: widget.unitId),
              ),
            ),

            // 2. Floating Top Header with Timer Badge & Title
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text(
                          'iVPN Premium Sponsor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Timer Badge
                      ValueListenableBuilder<int>(
                        valueListenable: _timeLeftNotifier,
                        builder: (context, timeLeft, child) {
                          if (timeLeft <= 0) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${timeLeft}s',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Floating Bottom Countdown Line
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: _timeLeftNotifier,
                builder: (context, timeLeft, child) {
                  if (timeLeft <= 0) return const SizedBox.shrink();
                  final progress = (15 - timeLeft) / 15.0;
                  return LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.black54,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                    minHeight: 4,
                  );
                },
              ),
            ),

            // 4. Escapability Layer: Close Button (Only appears after timer)
            ValueListenableBuilder<int>(
              valueListenable: _timeLeftNotifier,
              builder: (context, timeLeft, child) {
                if (timeLeft > 0) return const SizedBox.shrink();
                return Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Material(
                        color: Colors.black87,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.hardEdge,
                        child: Tooltip(
                          message: 'Close & Claim Reward',
                          child: ScaleOnTap(
                            onTap: () {
                              Navigator.of(context).pop(true);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
