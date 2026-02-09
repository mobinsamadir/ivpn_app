import 'package:flutter/material.dart';

/// A simple, robust error screen that displays a message and a retry button.
/// This screen is used when the main app fails to initialize or build.
class EmergencyApp extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;

  const EmergencyApp({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Application Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'An unexpected error occurred during startup:\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                // Optional Retry Button (if applicable)
                if (onRetry != null)
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
