import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/profile_api.dart';
import '../core/theme/theme.dart';
import '../data/app_repositories.dart';
import '../data/repository_exception.dart';
import '../models/engagement.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../widgets/follow_button.dart';
import '../widgets/paged_list.dart';
import '../widgets/states.dart';
import '../widgets/track_skeleton.dart';
import '../widgets/user_widgets.dart';
import 'auth_page.dart' show describeAuthError;
import 'track_actions.dart';

enum _ProfileTab { tracks, likes }

/// A user's page: a banner with their name and numbers, a follow button (or a rename button for oneself), and two lists —
/// their tracks and the tracks they liked. The user themselves also sees their private tracks here.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.userId});

  final String userId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  Object? _error;
  bool _loading = true;
  int? _trackTotal;
  _ProfileTab _tab = _ProfileTab.tracks;

  PagedController<Track>? _tracks;
  PagedController<Track>? _likes;
  String? _viewerId;
  bool _started = false;
  int _generation = 0;

  bool get _isMine => _viewerId != null && _viewerId == widget.userId;

  String get _tracksSource => 'user:${widget.userId}:tracks';
  String get _likesSource => 'user:${widget.userId}:likes';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewerId = context.viewerId;
    if (!_started) {
      _started = true;
      _viewerId = viewerId;
      _start();
    } else if (viewerId != _viewerId) {
      // What the viewer may see (private tracks) and "followed by me" are theirs: read it all again.
      _viewerId = viewerId;
      _start();
    }
  }

  void _start() {
    final repos = context.repos;
    final playback = context.playback;
    _tracks?.dispose();
    _likes?.dispose();
    _trackTotal = null;
    _tracks = PagedController<Track>(
      fetch: (cursor) async {
        final page = await repos.tracks.listUserTracks(widget.userId, cursor: cursor);
        if (cursor == null && mounted) setState(() => _trackTotal = page.totalCount);
        return PagedResult(page.items, page.nextCursor);
      },
      idOf: (t) => t.id,
      onAppended: (added) => playback.extendQueue(_tracksSource, added),
    );
    _likes = PagedController<Track>(
      fetch: (cursor) async {
        final page = await repos.feed.likedTracks(widget.userId, cursor: cursor);
        return PagedResult(page.items, page.nextCursor);
      },
      idOf: (t) => t.id,
      onAppended: (added) => playback.extendQueue(_likesSource, added),
    );
    _loadProfile();
    _tracks!.loadFirst();
    if (_tab == _ProfileTab.likes) _likes!.loadFirst();
  }

  Future<void> _loadProfile() async {
    final repos = context.repos;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await repos.users.getProfile(widget.userId);
      if (!mounted || generation != _generation) return;
      repos.directory.put(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tracks?.dispose();
    _likes?.dispose();
    super.dispose();
  }

  void _selectTab(_ProfileTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == _ProfileTab.likes && !_likes!.firstLoaded && !_likes!.loading) _likes!.loadFirst();
  }

  Future<void> _rename() async {
    final profile = _profile;
    if (profile == null) return;
    final repos = context.repos;
    final session = context.session;
    final account = await showDialog<Account>(
      context: context,
      builder: (_) => _RenameDialog(currentName: profile.displayName, repos: repos),
    );
    if (account == null || !mounted) return;
    session.accountChanged(account);
    final renamed = profile.copyWith(displayName: account.displayName);
    repos.directory.put(renamed);
    setState(() => _profile = renamed);
  }

  void _followChanged(FollowState state) {
    final profile = _profile;
    if (profile == null) return;
    final updated = profile.copyWith(isFollowedByMe: state.following, followerCount: state.followerCount);
    context.repos.directory.put(updated);
    setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) return const _ProfileSkeleton();
    final error = _error;
    if (error != null) {
      final notFound = error is RepositoryException && error.kind == RepositoryErrorKind.notFound;
      return Center(
        child: notFound
            ? EmptyState(
                key: const Key('userNotFound'),
                icon: Icons.person_off_outlined,
                title: 'Không tìm thấy người dùng',
                message: 'Người dùng này không tồn tại hoặc đã bị xoá.',
                action: FilledButton(key: const Key('goHomeButton'), onPressed: () => context.go('/'), child: const Text('Về trang chủ')),
              )
            : ErrorState.from(error, key: const Key('profileError'), onRetry: _loadProfile),
      );
    }
    final profile = _profile!;
    final controller = _tab == _ProfileTab.tracks ? _tracks! : _likes!;
    final sourceId = _tab == _ProfileTab.tracks ? _tracksSource : _likesSource;
    return PagedListView<Track>(
      key: ValueKey(_tab),
      controller: controller,
      skeleton: const TrackCardSkeleton(),
      header: _header(context, profile),
      empty: _empty(context, profile),
      itemBuilder: (context, track, index) => TrackTile(
        key: ValueKey('${_tab.name}-${track.id}'),
        track: track,
        queue: controller.items,
        index: index,
        sourceId: sourceId,
        onChanged: (updated) {
          for (final c in [_tracks!, _likes!]) {
            c.replace((t) => t.id == updated.id, (_) => updated);
          }
        },
        onDeleted: () {
          for (final c in [_tracks!, _likes!]) {
            c.removeWhere((t) => t.id == track.id);
          }
          setState(() {
            final total = _trackTotal;
            if (total != null && total > 0) _trackTotal = total - 1;
          });
        },
      ),
    );
  }

  Widget _header(BuildContext context, Profile profile) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final action = _isMine
        ? OutlinedButton.icon(
            key: const Key('renameButton'),
            onPressed: _rename,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Đổi tên'),
          )
        : FollowButton(
            userId: profile.userId,
            following: profile.isFollowedByMe,
            social: context.repos.social,
            viewerId: _viewerId,
            onNeedLogin: context.askToLogin,
            onChanged: _followChanged,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileHeader(
          profile: profile,
          action: action,
          trackCount: _trackTotal,
          onFollowers: () => context.go('/users/${Uri.encodeComponent(profile.userId)}/followers'),
          onFollowing: () => context.go('/users/${Uri.encodeComponent(profile.userId)}/following'),
        ),
        const SizedBox(height: AppSpacing.xl),
        SegmentedButton<_ProfileTab>(
          key: const Key('profileTabs'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _ProfileTab.tracks, label: Text('Bài hát', key: Key('tabTracks')), icon: Icon(Icons.music_note_rounded)),
            ButtonSegment(value: _ProfileTab.likes, label: Text('Đã thích', key: Key('tabLikes')), icon: Icon(Icons.favorite_border_rounded)),
          ],
          selected: {_tab},
          onSelectionChanged: (selected) => _selectTab(selected.first),
        ),
        if (_isMine && _tab == _ProfileTab.tracks) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: c.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text('Bài hát riêng tư chỉ mình bạn nhìn thấy ở đây.', key: const Key('privateNote'), style: text.bodySmall?.copyWith(color: c.textMuted))),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _empty(BuildContext context, Profile profile) {
    if (_tab == _ProfileTab.likes) {
      return EmptyState(
        key: const Key('likesEmpty'),
        icon: Icons.favorite_border_rounded,
        title: _isMine ? 'Bạn chưa thích bài nào' : '${profile.displayName} chưa thích bài nào',
        message: _isMine ? 'Bấm vào trái tim ở một bài hát để lưu nó ở đây.' : null,
      );
    }
    return EmptyState(
      key: const Key('tracksEmpty'),
      icon: Icons.library_music_outlined,
      title: _isMine ? 'Bạn chưa đăng bài hát nào' : '${profile.displayName} chưa đăng bài hát nào',
      message: _isMine ? 'Tải lên bản nhạc đầu tiên của bạn.' : null,
      action: _isMine
          ? FilledButton.icon(
              key: const Key('uploadFromEmpty'),
              onPressed: () => context.go('/upload'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Tải lên'),
            )
          : null,
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('profileLoading'),
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLoader(height: 160, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.xl),
          SkeletonLoader(width: 240, height: 28),
          SizedBox(height: AppSpacing.md),
          SkeletonLoader(width: 180, height: 16),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName, required this.repos});

  final String currentName;
  final AppRepositories repos;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.currentName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Hãy nhập tên hiển thị.');
      return;
    }
    if (name == widget.currentName) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = await widget.repos.users.changeDisplayName(name);
      if (mounted) Navigator.of(context).pop(account);
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() => _error = e.kind == RepositoryErrorKind.invalid ? describeAuthError(e.message).text : errorMessageFor(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: const Text('Đổi tên hiển thị'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('renameField'),
              controller: _name,
              autofocus: true,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Tên hiển thị'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, key: const Key('renameError'), style: TextStyle(color: c.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(key: const Key('cancelRenameButton'), onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(key: const Key('saveRenameButton'), onPressed: _saving ? null : _save, child: const Text('Lưu')),
      ],
    );
  }
}
