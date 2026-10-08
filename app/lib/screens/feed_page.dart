import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/theme.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../widgets/paged_list.dart';
import '../widgets/states.dart';
import '../widgets/track_skeleton.dart';
import 'track_actions.dart';

/// The new tracks of the people the user follows, newest first, a page at a time. It needs a login (the router sends a
/// visitor to the login page first). A user who follows nobody sees how to find someone.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  static const sourceId = 'feed';

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  PagedController<Track>? _controller;
  String? _viewerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewerId = context.viewerId;
    if (_controller == null) {
      _viewerId = viewerId;
      final feed = context.repos.feed;
      final playback = context.playback;
      _controller = PagedController<Track>(
        fetch: (cursor) async {
          final page = await feed.feed(cursor: cursor);
          return PagedResult(page.items, page.nextCursor);
        },
        idOf: (track) => track.id,
        onAppended: (added) => playback.extendQueue(FeedPage.sourceId, added),
      )..loadFirst();
    } else if (viewerId != _viewerId) {
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
    final controller = _controller!;
    final text = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return PagedListView<Track>(
      controller: controller,
      skeleton: const TrackCardSkeleton(),
      header: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bảng tin', key: const Key('feedTitle'), style: text.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Bài hát mới từ những người bạn theo dõi.', style: text.bodyMedium?.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
      empty: EmptyState(
        key: const Key('feedEmpty'),
        icon: Icons.dynamic_feed_rounded,
        title: 'Bảng tin của bạn đang trống',
        message: 'Hãy theo dõi vài nghệ sĩ để thấy bài hát mới của họ ở đây. Bạn có thể bắt đầu từ trang chủ.',
        action: FilledButton.icon(
          key: const Key('discoverButton'),
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Khám phá bài hát'),
        ),
      ),
      itemBuilder: (context, track, index) => TrackTile(
        key: ValueKey(track.id),
        track: track,
        queue: controller.items,
        index: index,
        sourceId: FeedPage.sourceId,
        onChanged: (updated) => controller.replace((t) => t.id == updated.id, (_) => updated),
        onDeleted: () => controller.removeWhere((t) => t.id == track.id),
      ),
    );
  }
}
