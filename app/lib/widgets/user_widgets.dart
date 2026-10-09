import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/profile_api.dart';
import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import 'cover_art.dart';
import 'user_avatar.dart';

/// A row for a user in a list (followers, search results): the avatar, the name, how many follow them, and something at
/// the end (usually a follow button).
class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.profile, this.onTap, this.trailing});

  final Profile profile;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            UserAvatar(userId: profile.userId, displayName: profile.displayName, imageUrl: profile.avatarUrl, size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  Text(
                    '${formatCount(profile.followerCount)} người theo dõi',
                    style: text.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpacing.md), trailing!],
          ],
        ),
      ),
    );
  }
}

/// A number with its name under it ("1,2K / Người theo dõi"). Pressing it opens the list, when there is one.
class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatCount(value),
              key: const Key('statValue'),
              style: text.titleLarge?.copyWith(fontFeatures: AppTypography.tabularFigures),
            ),
            Text(label, style: text.bodySmall?.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// The top of a profile page: a banner in the colours of the user, their avatar half over its edge, their name, how many
/// follow them and whom they follow, how many tracks they have, and a button (follow, or rename for oneself).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.action,
    this.trackCount,
    this.onFollowers,
    this.onFollowing,
  });

  final Profile profile;

  /// The follow button for another user, or a button to rename for the user themselves.
  final Widget action;

  /// How many tracks the viewer may see of this user; null while it is not known.
  final int? trackCount;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final compact = context.screenSize == ScreenSize.compact;
    final bannerHeight = compact ? 120.0 : 180.0;
    final avatar = compact ? 80.0 : 104.0;
    final (from, to) = CoverArt.gradientFor(profile.userId);
    final side = compact ? AppSpacing.lg : AppSpacing.xl;

    final stats = Wrap(
      spacing: AppSpacing.md,
      children: [
        StatBlock(key: const Key('statFollowers'), value: profile.followerCount, label: 'Người theo dõi', onTap: onFollowers),
        StatBlock(key: const Key('statFollowing'), value: profile.followingCount, label: 'Đang theo dõi', onTap: onFollowing),
        if (trackCount != null) StatBlock(key: const Key('statTracks'), value: trackCount!, label: 'Bài hát'),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              key: const Key('profileBanner'),
              height: bannerHeight,
              decoration: BoxDecoration(
                borderRadius: AppRadius.all(AppRadius.lg),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [from, to],
                ),
              ),
              // A soft dark fade at the bottom, so the avatar's edge reads on any colour.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.all(AppRadius.lg),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: side,
              bottom: -(avatar / 2 + 4),
              child: Container(
                key: const Key('profileAvatar'),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.background, shape: BoxShape.circle),
                child: UserAvatar(userId: profile.userId, displayName: profile.displayName, imageUrl: profile.avatarUrl, size: avatar),
              ),
            ),
          ],
        ),
        SizedBox(height: avatar / 2 + 4 + AppSpacing.md),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: math.max(0, side - AppSpacing.lg)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final name = Text(profile.displayName, key: const Key('profileName'), style: text.headlineMedium);
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, const SizedBox(height: AppSpacing.sm), stats, const SizedBox(height: AppSpacing.md), action],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, const SizedBox(height: AppSpacing.sm), stats],
                    ),
                  ),
                  action,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
