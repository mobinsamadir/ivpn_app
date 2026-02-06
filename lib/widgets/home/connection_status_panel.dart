// lib/widgets/home/connection_status_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/home_provider.dart';

class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final homeProvider = context.watch<HomeProvider>();
    final isConnected = homeProvider.isConnected;

    return Column(
      children: [
        const SizedBox(height: 40),
        GestureDetector(
          onTap: () => context.read<HomeProvider>().handleConnection(),
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: isConnected ? Colors.redAccent : Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? Colors.red : Colors.green).withOpacity(
                    0.4,
                  ),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Text(
                isConnected ? "DISCONNECT" : "CONNECT",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            homeProvider.statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}
