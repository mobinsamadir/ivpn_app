import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../models/testing/test_results.dart';

class StabilityChartScreen extends StatefulWidget {
  final String rawConfig;
  const StabilityChartScreen({super.key, required this.rawConfig});

  @override
  State<StabilityChartScreen> createState() => _StabilityChartScreenState();
}

class _StabilityChartScreenState extends State<StabilityChartScreen> {
  static const int _durationSeconds = 30;
  final List<double> _pings = <double>[];
  int _elapsed = 0;
  bool _running = false;
  double _packetLoss = 0.0;
  Timer? _countdownTimer;
  late final LatencyService _latencyService;

  @override
  void initState() {
    super.initState();
    _latencyService = LatencyService(WindowsVpnService());
    _startTest();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTest() async {
    if (!mounted) return;
    setState(() {
      _pings.clear();
      _elapsed = 0;
      _running = true;
      _packetLoss = 0.0;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_elapsed < _durationSeconds) {
        setState(() => _elapsed++);
      } else {
        t.cancel();
      }
    });

    try {
      final result = await _latencyService.runStabilityTest(
        widget.rawConfig,
        duration: const Duration(seconds: _durationSeconds),
        onSample: (latency) {
          if (mounted) {
            setState(() {
              // Map -1 (timeout) to 0.0 for the chart but track it for packet loss
              _pings.add(latency == -1 ? 0.0 : latency.toDouble());
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _packetLoss = result.stability?.packetLoss ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint("Stability test error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _countdownTimer?.cancel();
          _elapsed = _durationSeconds;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_durationSeconds - _elapsed).clamp(0, _durationSeconds);
    
    // Calculate stats from _pings
    final validPings = _pings.where((p) => p > 0).toList();
    final avg = validPings.isEmpty ? 0.0 : validPings.reduce((a, b) => a + b) / validPings.length;
    final minPing = validPings.isEmpty ? 0.0 : validPings.reduce(min);
    final maxPing = validPings.isEmpty ? 0.0 : validPings.reduce(max);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Stability Test (30s)', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Remaining: ${remaining.toString().padLeft(2, '0')}s',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      _running ? 'Testing...' : 'Completed',
                      style: TextStyle(
                        color: _running ? Colors.greenAccent : Colors.grey[300],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: CustomPaint(
                  painter: _PingLineChartPainter(_pings),
                  child: Container(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Samples', _pings.length.toString()),
                _buildStat('Loss', '${_packetLoss.toStringAsFixed(1)}%'),
                _buildStat('Min', '${minPing.toStringAsFixed(0)}ms'),
                _buildStat('Max', '${maxPing.toStringAsFixed(0)}ms'),
                _buildStat('Avg', '${avg.toStringAsFixed(0)}ms'),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _running ? null : _startTest,
              child: Text(_running ? 'Running...' : 'Run Again'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PingLineChartPainter extends CustomPainter {
  final List<double> pings;
  _PingLineChartPainter(this.pings);

  @override
  void paint(Canvas canvas, Size size) {
    if (pings.isEmpty) return;

    final axisPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1;

    // Draw grid lines
    for (int i = 0; i <= 5; i++) {
      final dy = size.height * i / 5;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), axisPaint);
    }

    final path = Path();
    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const leftPad = 8.0;
    const rightPad = 8.0;
    final width = size.width - leftPad - rightPad;

    // Use a reasonable defaults if all pings are 0 (e.g. all failed)
    final double maxPingVal = pings.reduce(max);
    final double displayMax = max(150.0, maxPingVal);
    final double displayMin = 0.0;

    for (int i = 0; i < pings.length; i++) {
      final x = leftPad + (i / max(1, pings.length - 1)) * width;
      final norm = ((pings[i] - displayMin) / (displayMax - displayMin)).clamp(0.0, 1.0);
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PingLineChartPainter oldDelegate) => true;
}
