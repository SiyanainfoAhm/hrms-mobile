import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/tokens.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 14, this.width, this.radius = 12});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF1F5F9),
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HrmsTokens.s4),
      decoration: BoxDecoration(
        color: HrmsTokens.surface,
        borderRadius: HrmsTokens.rLg(),
        border: Border.all(color: HrmsTokens.border),
        boxShadow: [HrmsTokens.shadowSm()],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 18, width: 140),
          const SizedBox(height: 14),
          for (var i = 0; i < lines; i++) ...[
            SkeletonBox(height: 12, width: i == lines - 1 ? 200 : double.infinity),
            if (i != lines - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
