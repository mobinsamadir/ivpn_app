
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/test_constants.dart';
import '../utils/cancellable_operation.dart';
import '../services/config_importer.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../services/singbox_config_generator.dart';
import '../models/testing/test_results.dart';
import '../services/testers/test_manager.dart';
import '../services/test_orchestrator.dart';
import '../services/test_job.dart';
// Remove or update the local _testQueue if it's used elsewhere.
import 'package:path/path.dart' as p;

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final _urlController = TextEditingController(
      text: "https://raw.githubusercontent.com/mamadz13/-IRAN_V2RAY1-IRAN_V2RAY1/refs/heads/main/@iran_v2ray1.txt");
  
  final List<String> _configs = [];
  final Map<int, ServerTestResult> _testResults = {}; // index -> result
  final Map<int, bool> _pingLoading = {};
  final Map<int, bool> _stabilityLoading = {};
  final Map<int, double> _stabilityProgress = {}; // index -> 0.0 to 1.0
  final Map<int, bool> _speedLoading = {};
  final Map<int, double> _speedProgress = {};
  final Map<int, double> _currentMbps = {};
  final Map<int, int> _remainingSeconds = {}; // index -> seconds remaining
  Timer? _countdownTimer;
  
  // No local _testQueue needed anymore
  final Map<int, CancelToken> _cancelTokens = {};
  
  final _vpnService = WindowsVpnService();
  late final LatencyService _latencyService; // Instance
  
  final double _bestSpeedMbps = 0.0;
  final ScrollController _logScrollController = ScrollController();
  final List<String> _logs = [];
  bool _isConnected = false;
  int? _activeConfigIndex;
  
  // Diagnostics
  bool _binFound = false;
  bool _geoIpFound = false;
  bool _geoSiteFound = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _latencyService = LatencyService(_vpnService); // Initialize
    _runDiagnostics();
    
    _vpnService.logStream.listen((log) {
      if (mounted) _log(log);
    });
  }

  Future<void> _runDiagnostics() async {
    try {
      final exePath = await _vpnService.getExecutablePath();
      final dir = p.dirname(exePath);
      
      setState(() {
        _binFound = File(exePath).existsSync();
        _geoIpFound = File(p.join(dir, 'geoip.db')).existsSync() || File(p.join(dir, 'geoip.dat')).existsSync();
        _geoSiteFound = File(p.join(dir, 'geosite.db')).existsSync() || File(p.join(dir, 'geosite.dat')).existsSync();
      });
      
      final admin = await _vpnService.isAdmin();
      setState(() => _isAdmin = admin);
      
    } catch (e) {
      _log("Diagnostic Error: $e");
    }
  }

  void _log(String msg) {
    setState(() => _logs.add(msg));
    // Auto-scroll
    if (_logScrollController.hasClients) {
      // Small delay to allow list to update
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_logScrollController.hasClients) {
           _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _fetchConfigs() async {
    _log("⬇️ Fetching Subscription...");
    final prevCount = _configs.length;
    try {
      final newConfigs = await ConfigImporter.fetchAndParse(_urlController.text);
      setState(() {
        for (var c in newConfigs) {
          if (!_configs.contains(c)) {
            _configs.add(c);
          }
        }
      });
      final added = _configs.length - prevCount;
      _log("✅ Loaded $added new configs. Total: ${_configs.length}");
    } catch (e) {
      _log("❌ Import Failed: $e");
    }
  }

  Future<void> _pingAll() async {
    _log("Please wait, pinging sequentially...");
    for (int i = 0; i < _configs.length; i++) {
      if (!mounted) break;
      await _pingItem(i);
      await Future.delayed(const Duration(milliseconds: 200)); // Cool down
    }
    _log("🏁 Ping batch complete.");
  }

  Future<void> _pingItem(int index) async {
    if (TestOrchestrator.pingQueue.isJobBusy(index)) {
      _showBusyNotice();
      return;
    }
    
    final cancelToken = CancelToken();
    _cancelTokens[index] = cancelToken;
    
    const timeout = TestTimeouts.pingCheck;
    
    TestOrchestrator.enqueuePingTest((token, jobId) async {
      if (mounted) {
        setState(() {
          _pingLoading[index] = true;
          _remainingSeconds[index] = timeout.inSeconds;
        });
      }
      
      try {
        final result = await _latencyService.getAdvancedLatency(
          _configs[index],
          onLog: (msg) => _log("[#$index] $msg"),
          jobId: jobId,
        );

        if (mounted) {
          setState(() {
            _testResults[index] = result;
            _pingLoading[index] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _pingLoading[index] = false);
          if (e is TimeoutException) {
             _log("⏰ Ping #$index timed out (${timeout.inSeconds}s)");
          } else {
             _log("❌ Ping Error #$index: $e");
          }
        }
      } finally {
        _cancelTokens.remove(index);
        if (mounted) {
          setState(() {
          _pingLoading[index] = false;
          _remainingSeconds.remove(index);
        });
        }
      }
    }, name: 'Ping Test #$index');
    
    _startCountdown(index, timeout.inSeconds);
  }

  void _startCountdown(int index, int totalSeconds) {
    // Basic logic: any existing countdown for THIS index should be replaced
    // This is simple enough to just run another periodic timer
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_remainingSeconds.containsKey(index)) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds[index]! > 0) {
          _remainingSeconds[index] = _remainingSeconds[index]! - 1;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _runStabilityTest(int index) async {
    if (TestOrchestrator.stabilityQueue.isJobBusy(index)) {
      _showBusyNotice();
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[index] = cancelToken;

    const timeout = TestTimeouts.stabilityTest;

    TestOrchestrator.enqueueStabilityTest((token, jobId) async {
      if (mounted) {
        setState(() {
          _stabilityLoading[index] = true;
          _stabilityProgress[index] = 0.0;
          _remainingSeconds[index] = timeout.inSeconds;
        });
      }

      try {
        final result = await _latencyService.runStabilityTest(
          _configs[index],
          onLog: (msg) => _log(msg),
          onProgress: (current, total) {
            if (mounted) {
              setState(() => _stabilityProgress[index] = current / total);
            }
          },
          cancelToken: cancelToken,
          jobId: jobId,
        );

        if (mounted) {
          setState(() {
            _testResults[index] = result;
            _stabilityLoading[index] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _stabilityLoading[index] = false);
          if (e is OperationCancelledException) {
            _log("⏹️ Stability test #$index cancelled.");
          } else if (e is TimeoutException) {
            _log("⏰ Stability test #$index timed out.");
          } else {
            _log("❌ Stability Test Error #$index: $e");
          }
        }
      } finally {
        _cancelTokens.remove(index);
        if (mounted) {
          setState(() {
          _stabilityLoading[index] = false;
          _remainingSeconds.remove(index);
        });
        }
      }
    }, name: 'Stability Test #$index');
    
    _startCountdown(index, timeout.inSeconds);
  }

  Future<void> _runSpeedTest(int index) async {
    if (TestOrchestrator.speedQueue.isJobBusy(index)) {
      _showBusyNotice();
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[index] = cancelToken;

    const timeout = TestTimeouts.speedTestSingle;

    TestOrchestrator.enqueueSpeedTest((token, jobId) async {
      if (mounted) {
        setState(() {
          _speedLoading[index] = true;
          _speedProgress[index] = 0.0;
          _currentMbps[index] = 0.0;
          _remainingSeconds[index] = timeout.inSeconds;
        });
      }

      try {
        final result = await _latencyService.runSpeedTest(
          _configs[index],
          onLog: (msg) => _log(msg),
          onProgress: (current, total, speed) {
            if (mounted) {
              setState(() {
                _speedProgress[index] = (current / total).clamp(0.0, 1.0);
                _currentMbps[index] = speed;
              });
            }
          },
          cancelToken: cancelToken,
          jobId: jobId,
        );

        if (mounted) {
          setState(() {
            _testResults[index] = result;
            _speedLoading[index] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _speedLoading[index] = false);
          if (e is OperationCancelledException) {
            _log("⏹️ Speed test #$index cancelled.");
          } else if (e is TimeoutException) {
            _log("⏰ Speed test #$index timed out.");
          } else {
            _log("❌ Speed Test Error #$index: $e");
          }
        }
      } finally {
        _cancelTokens.remove(index);
        if (mounted) {
          setState(() {
          _speedLoading[index] = false;
          _remainingSeconds.remove(index);
        });
        }
      }
    }, name: 'Speed Test #$index');
    
    _startCountdown(index, timeout.inSeconds);
  }

  Future<void> _pingAndTestSpeedFastest() async {
    _log("⚡ Starting 'Fastest First' Speed Test Mode...");
    
    // 1. Get candidates
    final List<int> candidates = List.generate(_configs.length, (i) => i);

    // Sort by latency if available
    candidates.sort((a, b) {
      final resA = _testResults[a]?.health.averageLatency ?? 9999;
      final resB = _testResults[b]?.health.averageLatency ?? 9999;
      final valA = resA == -1 ? 9999 : resA;
      final valB = resB == -1 ? 9999 : resB;
      return valA.compareTo(valB);
    });

    final topCandidates = candidates.take(10).toList();
    _log("🎯 Top 10 low-latency candidates identified.");

    int successes = 0;
    for (var index in topCandidates) {
      if (successes >= 3) {
        _log("✅ Found 3 high-performance servers. Stopping.");
        break;
      }

      if (!mounted) break;
      
      _log("🏎️ Testing speed for server #$index...");
      // Wrap in a CancellableOperation or use the queue
      await _runSpeedTest(index);
      
      final res = _testResults[index];
      if (res?.speed != null && (res?.speed?.downloadMbps ?? 0) > 0) {
        successes++;
        _log("💎 Success #$successes: ${res!.speed!.downloadMbps.toStringAsFixed(2)} Mbps");
      } else {
        _log("⚠️ Server #$index failed speed test or timed out. Skipping.");
      }
    }
    
    _log("🏁 Batch test complete.");
  }

  void _showBusyNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⚠️ This server is already under test. Please wait."),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleVpn(int index) async {
    if (_isConnected) {
      await _vpnService.stopVpn();
      setState(() {
        _isConnected = false;
        _activeConfigIndex = null;
      });
      return;
    }

    if (!_isAdmin) {
      _log("⛔ ADMIN REQUIRED: Run App/VSCode as Administrator!");
      return;
    }

    setState(() => _activeConfigIndex = index);
    
    try {
      final raw = _configs[index];
      // Note: startVpn now handles conversion internally
      await _vpnService.startVpn(raw);
      setState(() => _isConnected = true);
    } catch (e) {
      _log("❌ Start Failed: $e");
      setState(() => _activeConfigIndex = null);
    }
  }
  
  Future<void> _showSmartPasteDialog() async {
    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("➕ Smart Paste"),
        content: SizedBox(
          width: 600,
          child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               const Text("Paste ANYTHING here: mixed subscriptions, raw vmess, etc."),
               const SizedBox(height: 10),
               TextField(
                 controller: textController,
                 maxLines: 10,
                 decoration: const InputDecoration(
                   border: OutlineInputBorder(),
                   hintText: "vmess://...\nhttps://sub-link...",
                 ),
               ),
             ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _importSmart(textController.text);
            },
            child: const Text("Import"),
          ),
        ],
      ),
    );
  }

  Future<void> _importSmart(String rawInput) async {
     _log("🔄 Processing Smart Import...");
     final prevCount = _configs.length;
     
     try {
       final newConfigs = await ConfigImporter.parseInput(rawInput);
       setState(() {
         // Append distinctive new configs
         for(var c in newConfigs) {
           if (!_configs.contains(c)) _configs.add(c);
         }
         // Reset pings for new items if needed or just leave empty
       });
       
       final added = _configs.length - prevCount;
       _log("✅ Imported $added new configs. Total: ${_configs.length}");
       
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text("Added $added configs"), 
           backgroundColor: Colors.green
         ));
       }
       
     } catch (e) {
       _log("❌ Smart Import Error: $e");
     }
  }
  
  Future<void> _forceKill() async {
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
    _log("💀 Nuke complete. All processes killed.");
    setState(() {
      _isConnected = false;
      _activeConfigIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = TestOrchestrator.getStatus();
    final String queueStatus = "Queued: S:${status['speedQueue']} B:${status['stabilityQueue']}";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Windows Lab 🧪"),
        actions: [
           IconButton(
             icon: const Icon(Icons.refresh), 
             onPressed: _runDiagnostics,
             tooltip: "Re-check Diagnostics",
           ),
            IconButton(
              icon: const Icon(Icons.cleaning_services, color: Colors.orange),
              onPressed: () {
                TestOrchestrator.cancelAll();
                setState(() {
                  _pingLoading.clear();
                  _stabilityLoading.clear();
                  _speedLoading.clear();
                  _currentMbps.clear();
                  _speedProgress.clear();
                });
                _log("🧹 Queue cleared and states reset.");
              },
              tooltip: "Reset All Test States",
            ),
           IconButton(
             icon: const Icon(Icons.delete_forever, color: Colors.red),
             onPressed: _forceKill,
             tooltip: "Force Kill Singbox",
           )
        ],
      ),
      body: Column(
        children: [
          // 1. Diagnostics Panel
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statusChip("Binary", _binFound),
                _statusChip("GeoIP", _geoIpFound),
                _statusChip("GeoSite", _geoSiteFound),
                _statusChip("Admin", _isAdmin, warn: true),
              ],
            ),
          ),
          
          // 2. Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _urlController, decoration: const InputDecoration(labelText: "Sub URL", isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _fetchConfigs, child: const Text("Fetch")),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _showSmartPasteDialog, 
                  icon: const Icon(Icons.paste), 
                  label: const Text("Smart Paste")
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _configs.isEmpty ? null : _pingAll, child: const Text("Ping All")),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _configs.isEmpty ? null : _pingAndTestSpeedFastest, 
                  icon: const Icon(Icons.bolt, color: Colors.amber),
                  label: const Text("Speed (Top 10)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // 3. Config List
          Expanded(
            flex: 3,
            child: ListView.separated(
              itemCount: _configs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final link = _configs[i];
                final loading = _pingLoading[i] ?? false;
                final isActive = _activeConfigIndex == i;
                
                // Parse Name (Fragment)
                String name = "Config $i";
                try { name = Uri.parse(link).fragment; } catch (_) {}
                if (name.isEmpty) name = "Config #$i";
                
                return ExpansionTile(
                  key: ValueKey(link),
                  initiallyExpanded: false,
                  title: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Uri.decodeComponent(name), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(link.split("://").first.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (loading) 
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                            if (_remainingSeconds.containsKey(i))
                              Text("${_remainingSeconds[i]}s", style: const TextStyle(fontSize: 10, color: Colors.blue)),
                          ],
                        )
                      else if (_testResults.containsKey(i))
                        _buildHealthChip(_testResults[i]!)
                      else 
                        const Text("-", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isActive ? Colors.green : Colors.grey.shade300,
                    radius: 4,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: "Copy raw config",
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: link));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Config copied to clipboard')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.network_check, size: 20),
                        tooltip: "Quick Health Check",
                        onPressed: () => _pingItem(i),
                      ),
                      const VerticalDivider(),
                      TextButton(
                         onPressed: isActive ? () => _toggleVpn(i) : (_isConnected ? null : () => _toggleVpn(i)),
                         child: Text(isActive ? "STOP" : "CONNECT"),
                      )
                    ],
                  ),
                  children: [
                    _buildStabilityDetails(i),
                  ],
                );
              },
            ),
          ),
          
          // Best Speed and Queue Status
          if (status['speedQueue'] > 0 || status['stabilityQueue'] > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
                ),
                child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  queueStatus,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          if (_bestSpeedMbps > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.star, size: 16, color: Colors.amber),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Best Speed: ${_bestSpeedMbps.toStringAsFixed(2)} Mbps",
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),

          Text(
            "Debug Logs",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(thickness: 4),
          
          // 4. Log Panel
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _logs.length,
                itemBuilder: (ctx, i) => Text(
                  _logs[i], 
                  style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Consolas', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStabilityDetails(int index) {
    final result = _testResults[index];
    final bool isBusy = TestOrchestrator.stabilityQueue.isJobBusy(index) || TestOrchestrator.speedQueue.isJobBusy(index);
    final String label = isBusy ? "Stop" : "Ping";
    final progress = _stabilityProgress[index] ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blueGrey.withOpacity(0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Stability Monitor (30s Test)", style: TextStyle(fontWeight: FontWeight.bold)),
              if (isBusy)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      child: LinearProgressIndicator(value: progress),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.red, size: 20),
                      onPressed: () => _cancelTokens[index]?.cancel(),
                      tooltip: "Cancel Test",
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _runStabilityTest(index),
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text("Run Test"),
                  style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (result?.stability != null && !isBusy) ...[
            _buildStabilityStats(result!.stability!),
            const SizedBox(height: 12),
            _buildStabilityChart(result.stability!.samples),
          ] else if (!isBusy)
            const Text("No stability data collected yet.", style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            const Text("Testing in progress... click STOP to cancel.", style: TextStyle(fontSize: 12, color: Colors.blue)),
          
          const Divider(height: 32),

          // Speed Test Section
          _buildSpeedTestSection(index),
        ],
      ),
    );
  }

  Widget _buildSpeedTestSection(int index) {
    final result = _testResults[index];
    final loading = _speedLoading[index] ?? false;
    final progress = _speedProgress[index] ?? 0.0;
    final currentSpeed = _currentMbps[index] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Adaptive Speed Test", style: TextStyle(fontWeight: FontWeight.bold)),
            if (loading)
              Row(
                children: [
                  Text("${currentSpeed.toStringAsFixed(1)} Mbps", style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  SizedBox(width: 60, child: LinearProgressIndicator(value: progress)),
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, color: Colors.red, size: 20),
                    onPressed: () => _cancelTokens[index]?.cancel(),
                    tooltip: "Cancel Speed Test",
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: () => _runSpeedTest(index),
                icon: const Icon(Icons.speed, size: 16),
                label: const Text("Run Speed"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (result?.speed != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem("Download", "${result!.speed!.downloadMbps.toStringAsFixed(2)} Mbps", Colors.green),
                _statItem("Time", "${result.speed!.downloadDuration.inSeconds}s", Colors.blueGrey),
                _statItem("Method", result.speed!.testFileUsed, Colors.blue),
              ],
            ),
          )
        else if (!loading)
          const Text("Test speed to see performance.", style: TextStyle(fontSize: 12, color: Colors.grey))
      ],
    );
  }

  Widget _buildStabilityStats(StabilityMetrics s) {
    return Wrap(
      spacing: 20,
      runSpacing: 10,
      children: [
        _statItem("Jitter", "${s.jitter.toStringAsFixed(2)}ms", Colors.orange),
        _statItem("Loss", "${s.packetLoss.toStringAsFixed(1)}%", Colors.red),
        _statItem("Min/Max", "${s.minLatency}/${s.maxLatency}ms", Colors.blue),
        _statItem("StdDev", s.standardDeviation.toStringAsFixed(2), Colors.purple),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildStabilityChart(List<int> samples) {
    if (samples.isEmpty) return const SizedBox();
    
    // Normalize samples for simple bar display
    final maxVal = samples.reduce((a, b) => a > b ? a : b);
    final displayMax = maxVal > 0 ? maxVal : 1;

    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: samples.map((s) {
          final heightFactor = s == -1 ? 1.0 : (s / displayMax).clamp(0.05, 1.0);
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              height: 60 * heightFactor,
              color: s == -1 ? Colors.red : Colors.green.withOpacity(0.6),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHealthChip(ServerTestResult result) {
    final health = result.health;
    final ms = health.averageLatency;
    final total = health.endpointLatencies.length;
    final okCount = health.endpointLatencies.values.where((v) => v > 0).length;
    
    final color = ms == -1 ? Colors.red : (ms < 200 ? Colors.green : (ms < 500 ? Colors.orange : Colors.red));
    
    return Tooltip(
      richMessage: TextSpan(
        text: "Health Details:\n",
        style: const TextStyle(fontWeight: FontWeight.bold),
        children: health.endpointLatencies.entries.map((e) {
          final isOk = e.value > 0;
          return TextSpan(
            text: "\n• ${e.key}: ${isOk ? "${e.value}ms" : "FAILED"}",
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: isOk ? Colors.greenAccent : Colors.redAccent,
            ),
          );
        }).toList(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(ms == -1 ? "Fail" : "${ms}ms", 
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)
          ),
          Text("$okCount/$total OK", 
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w500)
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool ok, {bool warn = false}) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      avatar: Icon(ok ? Icons.check_circle : (warn ? Icons.warning : Icons.error), 
        color: ok ? Colors.green : (warn ? Colors.orange : Colors.red), size: 16),
      backgroundColor: Colors.white,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
