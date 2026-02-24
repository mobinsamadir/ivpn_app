import 'package:flutter/material.dart';
import 'shimmer_config_card.dart';

class ShimmerList extends StatelessWidget {
  const ShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) => const ShimmerConfigCard(),
    );
  }
}
