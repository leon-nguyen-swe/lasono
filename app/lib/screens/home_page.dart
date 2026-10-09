import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/theme.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../widgets/paged_list.dart';
import '../widgets/states.dart';
import '../widgets/track_skeleton.dart';
import 'track_actions.dart';

/// The newest tracks, a page at a time. Playing one makes the whole list the queue, and the queue grows as the list
/// loads more. When the logged-in user changes the list is read again, because what a user may see (their own private
/// tracks) is different for each.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const sourceId = 'home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PagedController<Track>? _controller;
  String? _viewerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewerId = context.viewerId;
    if (_controller == null) {
      final tracks = context.repos.tracks;
      final playback = context.playback;
      _viewerId = viewerId;
      _controller = PagedController<Track>(
        fetch: (cursor) async {
          final page = await tracks.listTracks(cursor: cursor);
          return PagedResult(page.items, page.nextCursor);
        },
        idOf: (track) => track.id,
        onAppended: (added) => playback.extendQueue(HomePage.sourceId, added),
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
            Text('Mới nhất', key: const Key('homeTitle'), style: text.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Những bài hát vừa được đăng lên LaSono.', style: text.bodyMedium?.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
      empty: EmptyState(
        key: const Key('homeEmpty'),
        icon: Icons.library_music_outlined,
        title: 'Chưa có bài hát nào',
        message: 'Hãy là người đầu tiên chia sẻ một bản nhạc.',
        action: FilledButton.icon(
          key: const Key('uploadFromEmpty'),
          onPressed: () => context.go('/upload'),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Tải lên'),
        ),
      ),
      itemBuilder: (context, track, index) => TrackTile(
        key: ValueKey(track.id),
        track: track,
        queue: controller.items,
        index: index,
        sourceId: HomePage.sourceId,
        onChanged: (updated) => controller.replace((t) => t.id == updated.id, (_) => updated),
        onDeleted: () => controller.removeWhere((t) => t.id == track.id),
      ),
    );
  }
}
