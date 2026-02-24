import 'package:flutter/material.dart';

class ShimmerConfigCard extends StatefulWidget {
  const ShimmerConfigCard({super.key});

  @override
  State<ShimmerConfigCard> createState() => _ShimmerConfigCardState();
}

class _ShimmerConfigCardState extends State<ShimmerConfigCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: const Color(0xFF2A2A2A),
      end: const Color(0xFF3A3A3A),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, child) {
        final color = _colorAnimation.value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              // Flag Placeholder
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              // Content Placeholder
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                         color: color,
                         borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Metrics Row
                    Row(
                       children: [
                          Container(width: 60, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 8),
                          Container(width: 40, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                       ],
                    )
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Actions Placeholder
              Column(
                 children: [
                    Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(height: 8),
                    Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                 ],
              )
            ],
          ),
        );
      },
    );
  }
}
