import 'dart:async';
import 'package:flutter/material.dart';
import 'universal_ad_widget.dart';
import '../services/ad_manager_service.dart';
import '../services/config_gist_service.dart';
import 'scale_on_tap.dart';

class FullScreenAdDialog extends StatefulWidget {
  final String unitId;

  const FullScreenAdDialog({super.key, this.unitId = 'reward_ad'});

  @override
  State<FullScreenAdDialog> createState() => _FullScreenAdDialogState();
}

class _FullScreenAdDialogState extends State<FullScreenAdDialog> {
  int _totalDuration = 20;
  late final ValueNotifier<int> _timeLeftNotifier;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _totalDuration = ConfigGistService.rewardAdDurationSeconds;
    _timeLeftNotifier = ValueNotifier<int>(_totalDuration);
    _initDurationAndStartTimer();
  }

  Future<void> _initDurationAndStartTimer() async {
    final configured = await ConfigGistService.getRewardAdDurationSeconds();
    if (mounted && configured != _totalDuration && _timeLeftNotifier.value == _totalDuration) {
      setState(() {
        _totalDuration = configured;
        _timeLeftNotifier.value = configured;
      });
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
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
            // 0. Branded Fallback / Sponsor Background Layer (Original iVPN Brand)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF020617)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E293B),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.25),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'iVPN Sponsor Network',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Community Sponsored Secure Access',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: const Text(
                            'Providing fast and secure private internet access for everyone',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 1. True Fullscreen Ad Layer (100% of Screen)
            Positioned.fill(
              child: UniversalAdWidget(slot: widget.unitId),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              color: Colors.blueAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'iVPN Sponsor Network',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Timer Badge
                      ValueListenableBuilder<int>(
                        valueListenable: _timeLeftNotifier,
                        builder: (context, timeLeft, child) {
                          if (timeLeft <= 0) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  color: Colors.white,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${timeLeft}s',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
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
                  final progress = _totalDuration > 0
                      ? (_totalDuration - timeLeft) / _totalDuration
                      : 1.0;
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
                      padding: const EdgeInsets.all(10.0),
                      child: ScaleOnTap(
                        onTap: () {
                          Navigator.of(context).pop(true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.5),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Claim Reward',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
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
