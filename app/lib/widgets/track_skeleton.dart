import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import 'states.dart';

/// What a [TrackCard] looks like while it is not there yet: a cover and a few lines. Used by every list of tracks.
class TrackCardSkeleton extends StatelessWidget {
  const TrackCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      key: const Key('trackCardSkeleton'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: c.outline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLoader(width: 96, height: 96, radius: AppRadius.md),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 220, height: 18),
                SizedBox(height: AppSpacing.sm),
                SkeletonLoader(width: 120, height: 14),
                SizedBox(height: AppSpacing.lg),
                SkeletonLoader(height: 48, radius: AppRadius.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
