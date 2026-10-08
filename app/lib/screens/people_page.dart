import 'package:flutter/material.dart';

import '../api/profile_api.dart';
import '../core/theme/theme.dart';
import '../shell/app_context.dart';
import '../widgets/follow_button.dart';
import '../widgets/paged_list.dart';
import '../widgets/states.dart';
import '../widgets/user_widgets.dart';

enum PeopleKind { followers, following }

/// The people who follow a user, or the people a user follows, a page at a time. Each row has a follow button, so the
/// viewer can follow back from here.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.userId, required this.kind});

  final String userId;
  final PeopleKind kind;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  PagedController<Profile>? _controller;
  String? _viewerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewerId = context.viewerId;
    if (_controller == null) {
      _viewerId = viewerId;
      final repos = context.repos;
      repos.directory.profile(widget.userId).then((_) {}, onError: (_) {});
      _controller = PagedController<Profile>(
        fetch: (cursor) async {
          final page = widget.kind == PeopleKind.followers
              ? await repos.social.followers(widget.userId, cursor: cursor)
              : await repos.social.following(widget.userId, cursor: cursor);
          // One request for all the names of the page; a user who no longer exists is left out.
          final profiles = await repos.directory.profiles(page.items.map((edge) => edge.userId));
          return PagedResult([for (final edge in page.items) ?profiles[edge.userId]], page.nextCursor);
        },
        idOf: (profile) => profile.userId,
      )..loadFirst();
    } else if (viewerId != _viewerId) {
      // Who the viewer follows is theirs: the buttons must be read again.
      _viewerId = viewerId;
      _controller!.loadFirst();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    final repos = context.repos;
    final followers = widget.kind == PeopleKind.followers;
    return PagedListView<Profile>(
      controller: _controller!,
      itemGap: AppSpacing.xs,
      skeleton: const _PersonSkeleton(),
      skeletonCount: 6,
      header: ListenableBuilder(
        listenable: repos.directory,
        builder: (context, _) {
          final name = repos.directory.nameOf(widget.userId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                key: const Key('backToProfile'),
                onPressed: () => context.openUser(widget.userId),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(name.isEmpty ? 'Về trang cá nhân' : 'Về trang của $name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(followers ? 'Người theo dõi' : 'Đang theo dõi', key: const Key('peopleTitle'), style: text.headlineMedium),
              if (name.isNotEmpty)
                Text(
                  followers ? 'Những người đang theo dõi $name' : 'Những người $name đang theo dõi',
                  style: text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
      empty: EmptyState(
        key: const Key('peopleEmpty'),
        icon: Icons.people_outline_rounded,
        title: followers ? 'Chưa có ai theo dõi' : 'Chưa theo dõi ai',
        message: followers ? 'Khi có người theo dõi, họ sẽ xuất hiện ở đây.' : 'Những người được theo dõi sẽ xuất hiện ở đây.',
      ),
      itemBuilder: (context, profile, index) => UserTile(
        key: ValueKey(profile.userId),
        profile: profile,
        onTap: () => context.openUser(profile.userId),
        trailing: profile.userId == context.viewerId
            ? null
            : FollowButton(
                userId: profile.userId,
                following: profile.isFollowedByMe,
                social: repos.social,
                viewerId: context.viewerId,
                onNeedLogin: context.askToLogin,
                compact: true,
                onChanged: (state) => repos.directory.put(profile.copyWith(isFollowedByMe: state.following, followerCount: state.followerCount)),
              ),
      ),
    );
  }
}

class _PersonSkeleton extends StatelessWidget {
  const _PersonSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('personSkeleton'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      child: Row(
        children: [
          SkeletonLoader(width: 48, height: 48, circle: true),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 160, height: 16),
                SizedBox(height: AppSpacing.xs),
                SkeletonLoader(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
