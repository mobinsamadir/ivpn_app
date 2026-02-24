import 'package:flutter/material.dart';
import 'shimmer_config_card.dart';

class ShimmerList extends StatelessWidget {
  const ShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListView.builder(
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(),
        // Rendering Optimization: RepaintBoundary
        itemBuilder: (context, index) => const RepaintBoundary(child: ShimmerConfigCard()),
      ),
    );
  }
}
