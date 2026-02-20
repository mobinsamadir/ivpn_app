import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  final String statusMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const SplashScreen({
    super.key,
    this.statusMessage = 'Initializing...',
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900], // Dark theme background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Icon(Icons.vpn_lock, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              
              // Status or Error
              if (errorMessage != null) ...[
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
                const SizedBox(height: 24),
                if (onRetry != null)
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                  )
              ] else ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 24),
                Text(
                  statusMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
