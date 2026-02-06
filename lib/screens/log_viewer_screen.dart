import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/advanced_logger.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, color: Colors.green),
            onPressed: _copyAllLogs,
            tooltip: 'Copy All Logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: _clearLogs,
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<List<String>>(
        valueListenable: AdvancedLogger.logNotifier,
        builder: (context, logs, child) {
          // Scroll to bottom when new logs arrive
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
          
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.grey[900],
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'Showing last ${logs.length} log entries',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    Color textColor = Colors.green; // Default green
                    
                    // Color code based on log level
                    if (log.contains('[ERROR]')) {
                      textColor = Colors.red;
                    } else if (log.contains('[WARN]')) {
                      textColor = Colors.orange;
                    } else if (log.contains('[DEBUG]')) {
                      textColor = Colors.cyan;
                    }
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      child: Text(
                        log,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyAllLogs() async {
    final logs = AdvancedLogger.logNotifier.value;
    final logText = logs.join('\n');
    
    await Clipboard.setData(ClipboardData(text: logText));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    AdvancedLogger.logNotifier.value = [];
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs cleared'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}