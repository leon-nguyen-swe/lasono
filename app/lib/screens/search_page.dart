import 'package:flutter/material.dart';

import '../api/profile_api.dart';
import '../core/theme/theme.dart';
import '../models/search_results.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../widgets/follow_button.dart';
import '../widgets/states.dart';
import '../widgets/track_skeleton.dart';
import '../widgets/user_widgets.dart';
import 'track_actions.dart';

/// Search over tracks and people. The words come from the address (`/search?q=son`), which the search box of the top bar
/// sets after a short pause, so a result page can be linked and the back button works. The tabs choose what to show: all,
/// only tracks, or only people. Accents and case do not matter (`son tung` finds `Sơn Tùng`) and the part that matched is
/// highlighted.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.query});

  /// What the user typed, as it is in the address.
  final String query;

  /// The least a search takes (the server refuses less).
  static const minLength = 2;

  /// How many of each kind the "all" tab shows, and how many a tab of one kind asks for.
  static const overviewLimit = 6;
  static const tabLimit = 30;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  SearchType _type = SearchType.all;
  SearchResults? _results;
  Object? _error;
  bool _loading = false;
  int _generation = 0;
  String? _viewerId;
  bool _started = false;

  String get _query => widget.query.trim();
  bool get _searchable => _query.length >= SearchPage.minLength;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewerId = context.viewerId;
    if (!_started) {
      _started = true;
      _viewerId = viewerId;
      _search();
    } else if (viewerId != _viewerId) {
      // Who is followed and what is liked belong to the viewer: ask again.
      _viewerId = viewerId;
      _search();
    }
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.trim() != widget.query.trim()) _search();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    if (!_searchable) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final search = context.repos.search;
    final type = _type;
    final query = _query;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await search.search(query, type: type, limit: type == SearchType.all ? SearchPage.overviewLimit : SearchPage.tabLimit);
      // A slower answer to an older query must not replace the newer one.
      if (!mounted || generation != _generation) return;
      context.repos.directory.cachedAll(results.users);
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectType(SearchType type) {
    if (type == _type) return;
    setState(() => _type = type);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return ListView(
      key: const Key('searchList'),
      padding: EdgeInsets.symmetric(
        horizontal: (MediaQuery.sizeOf(context).width - AppBreakpoints.contentMaxWidth).clamp(0, 10000) / 2 + AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      children: [
        Text(_searchable ? 'Kết quả cho “$_query”' : 'Tìm kiếm', key: const Key('searchTitle'), style: text.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        if (_searchable) ...[
          SegmentedButton<SearchType>(
            key: const Key('searchTabs'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: SearchType.all, label: Text('Tất cả', key: Key('tabAll'))),
              ButtonSegment(value: SearchType.tracks, label: Text('Bài hát', key: Key('tabTracks'))),
              ButtonSegment(value: SearchType.users, label: Text('Người dùng', key: Key('tabUsers'))),
            ],
            selected: {_type},
            onSelectionChanged: (selected) => _selectType(selected.first),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        ..._body(context, text, c),
      ],
    );
  }

  List<Widget> _body(BuildContext context, TextTheme text, AppColors c) {
    if (_query.isEmpty) {
      return const [
        EmptyState(
          key: Key('searchIdle'),
          icon: Icons.search_rounded,
          title: 'Tìm bài hát và nghệ sĩ',
          message: 'Gõ vào ô tìm kiếm phía trên. Không cần gõ dấu: “son tung” cũng tìm ra “Sơn Tùng”.',
        ),
      ];
    }
    if (!_searchable) {
      return const [
        EmptyState(
          key: Key('searchTooShort'),
          icon: Icons.keyboard_outlined,
          title: 'Hãy gõ thêm một chút',
          message: 'Cần ít nhất 2 ký tự để tìm kiếm.',
        ),
      ];
    }
    final error = _error;
    if (error != null) return [ErrorState.from(error, key: const Key('searchError'), onRetry: _search)];
    final results = _results;
    if (_loading && results == null) {
      return [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.lg), child: const TrackCardSkeleton())];
    }
    if (results == null) return const [];
    if (results.isEmpty) {
      return [
        EmptyState(
          key: const Key('searchEmpty'),
          icon: Icons.search_off_rounded,
          title: 'Không có kết quả cho “$_query”',
          message: 'Thử một từ khác, hoặc kiểm tra lại chính tả.',
        ),
      ];
    }

    final showTracks = _type != SearchType.users && results.tracks.isNotEmpty;
    final showUsers = _type != SearchType.tracks && results.users.isNotEmpty;
    return [
      // While a newer answer is on its way the old one stays, dimmed, instead of jumping to a spinner.
      Opacity(
        opacity: _loading ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showUsers) ...[
              Text('Người dùng', key: const Key('usersHeading'), style: text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              for (final profile in results.users) _userRow(context, profile),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (showTracks) ...[
              Text('Bài hát', key: const Key('tracksHeading'), style: text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              for (final (index, track) in results.tracks.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _trackRow(track, results.tracks, index),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _userRow(BuildContext context, Profile profile) {
    final repos = context.repos;
    return UserTile(
      key: ValueKey('user-${profile.userId}'),
      profile: profile,
      highlight: _query,
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
    );
  }

  Widget _trackRow(Track track, List<Track> all, int index) => TrackTile(
        key: ValueKey('track-${track.id}'),
        track: track,
        queue: all,
        index: index,
        sourceId: 'search:$_query',
        highlight: _query,
        onChanged: (updated) => setState(() {
          _results = SearchResults(
            tracks: [for (final t in _results!.tracks) t.id == updated.id ? updated : t],
            users: _results!.users,
          );
        }),
        onDeleted: () => setState(() {
          _results = SearchResults(tracks: _results!.tracks.where((t) => t.id != track.id).toList(), users: _results!.users);
        }),
      );
}
