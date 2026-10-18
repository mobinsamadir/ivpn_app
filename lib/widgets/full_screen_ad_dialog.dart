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
        backgroundColor: const Color(0xFF0F172A),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF020617)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // 1. Top Bar: Header with "iVPN Sponsor Network" and Timer / Claim Reward
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_user_rounded, color: Colors.blueAccent, size: 16),
                            SizedBox(width: 8),
                            Text(
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
                      // Timer or Claim Reward button
                      ValueListenableBuilder<int>(
                        valueListenable: _timeLeftNotifier,
                        builder: (context, timeLeft, _) {
                          if (timeLeft <= 0) {
                            return ScaleOnTap(
                              onTap: () => Navigator.of(context).pop(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                const Icon(Icons.timer_outlined, color: Colors.white, size: 15),
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

                // 2. Middle Card: Branded Sponsor Message (Always Visible from Second 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        padding: const EdgeInsets.all(10),
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
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Community Sponsored Access',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Watch sponsor content to earn 1 hour of high-speed connection',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // 3. Ad Container (Embedded cleanly, responsive)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: UniversalAdWidget(slot: widget.unitId),
                      ),
                    ),
                  ),
                ),

                // 4. Floating Bottom Countdown Line
                ValueListenableBuilder<int>(
                  valueListenable: _timeLeftNotifier,
                  builder: (context, timeLeft, _) {
                    if (timeLeft <= 0) return const SizedBox.shrink();
                    final progress = _totalDuration > 0
                        ? (_totalDuration - timeLeft) / _totalDuration
                        : 1.0;
                    return LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.black54,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      minHeight: 4,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
