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
  bool _canClose = false;
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
    // PopScope prevents Back Button to enforce "The Wall"
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
         if (didPop) return;
         // Optionally block interaction or show toast
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _canClose ? Colors.green : Colors.redAccent.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                           Icon(_canClose ? Icons.check : Icons.timer, color: Colors.white, size: 14),
                           const SizedBox(width: 6),
                           Text(
                            _canClose ? 'Ready' : '${_timeLeft}s',
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
                  color: const Color(0xFF121212),
                  child: Center(
                    child: UniversalAdWidget(slot: widget.unitId),
                  ),
                ),
              ),

              // Footer "The Wall" Action Area
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
                        ? "Thank you! You can now connect."
                        : "Your premium connection is ready in ${_timeLeft}s...",
                      style: TextStyle(
                        color: _canClose ? Colors.greenAccent : Colors.grey[400],
                        fontSize: 14,
                        fontWeight: FontWeight.w500
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canClose
                            ? () => Navigator.of(context).pop(true)
                            : null, // Disabled until timer ends
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          disabledBackgroundColor: Colors.grey[800],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: _canClose ? 4 : 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!_canClose)
                              const Padding(
                                padding: EdgeInsets.only(right: 12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white38)
                                ),
                              ),
                            Text(
                              _canClose ? 'CONNECT NOW' : 'PLEASE WAIT...',
                              style: TextStyle(
                                color: _canClose ? Colors.white : Colors.white38,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
