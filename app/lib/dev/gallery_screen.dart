import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../api/profile_api.dart';
import '../data/app_repositories.dart';
import '../data/fake/fake_behavior.dart';
import '../data/fake/fake_repositories.dart';
import '../data/fake/fake_world.dart';
import '../data/user_directory.dart';
import '../data/waveform_cache.dart';
import '../playback/playback_controller.dart';
import '../widgets/comments.dart';
import '../widgets/cover_art.dart';
import '../widgets/follow_button.dart';
import '../widgets/like_button.dart';
import '../widgets/states.dart';
import '../widgets/track_card.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_widgets.dart';
import '../widgets/waveform_view.dart';

/// Every design token and component on one page, in the current theme. Only for development (the route
/// exists in debug builds), to look at the design system without going through the app.
///
/// Open it at `/#/dev/gallery` while `flutter run` is serving the app. New components are added here as a
/// [_Section] when they are built.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key, required this.themeController, this.embedded = false});

  static const routeName = '/dev/gallery';

  final ThemeController themeController;

  /// True when the page is shown inside the app shell, which already has a top bar: then it has no bar of its own.
  final bool embedded;

  static const _sections = <Widget>[
    _ColorsSection(),
    _TypographySection(),
    _SpacingSection(),
    _ShapeSection(),
    _MotionSection(),
    _BreakpointSection(),
    _PlayerSection(),
    _ComponentsSection(),
    _AppComponentsSection(),
  ];

  Widget _themeSwitch() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dark_mode_outlined, size: 18),
          Switch(
            key: const Key('lightModeSwitch'),
            value: themeController.mode == ThemeMode.light,
            onChanged: (_) => themeController.toggle(),
          ),
          const Icon(Icons.light_mode_outlined, size: 18),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final list = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                if (embedded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: Row(
                      children: [
                        Expanded(child: Text('Design system', style: Theme.of(context).textTheme.displaySmall)),
                        _themeSwitch(),
                      ],
                    ),
                  ),
                ..._sections,
              ],
            ),
          ),
        );
        if (embedded) return list;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Design system'),
            actions: [Padding(padding: const EdgeInsets.only(right: AppSpacing.lg), child: _themeSwitch())],
          ),
          body: list,
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineMedium),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note!, style: text.bodySmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _ColorsSection extends StatelessWidget {
  const _ColorsSection();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // name, colour, the colour it is read against (so the ratio shown is the one that matters)
    final swatches = <(String, Color, Color)>[
      ('background', c.background, c.textPrimary),
      ('surface', c.surface, c.textPrimary),
      ('surfaceRaised', c.surfaceRaised, c.textPrimary),
      ('surfaceHigh', c.surfaceHigh, c.textPrimary),
      ('outline', c.outline, c.textPrimary),
      ('inputBorder', c.inputBorder, c.background),
      ('textPrimary', c.textPrimary, c.background),
      ('textSecondary', c.textSecondary, c.background),
      ('textMuted', c.textMuted, c.background),
      ('accent', c.accent, c.background),
      ('accentHover', c.accentHover, c.onAccent),
      ('onAccent', c.onAccent, c.accent),
      ('success', c.success, c.background),
      ('warning', c.warning, c.background),
      ('error', c.error, c.background),
      ('waveformPlayed', c.waveformPlayed, c.surface),
      ('waveformUnplayed', c.waveformUnplayed, c.surface),
      ('waveformHover', c.waveformHover, c.surface),
    ];
    return _Section(
      title: 'Colours',
      note: 'The ratio under each name is against the colour it is read on (WCAG: 4.5 for text, 3 for graphics).',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final (name, colour, against) in swatches)
            _Swatch(name: name, colour: colour, against: against),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.colour, required this.against});

  final String name;
  final Color colour;
  final Color against;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final hex = '#${colour.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: AppRadius.all(AppRadius.md),
              border: Border.all(color: c.outline),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(name, style: text.labelLarge),
          Text('$hex · ${contrastRatio(colour, against).toStringAsFixed(1)}:1', style: text.bodySmall),
        ],
      ),
    );
  }
}

class _TypographySection extends StatelessWidget {
  const _TypographySection();

  static const _sample = 'Nắng ấm xa dần · Sơn Tùng M-TP · Đen Vâu — ặ ế ữ ơ ư đ';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final styles = <(String, TextStyle?)>[
      ('displaySmall', t.displaySmall),
      ('headlineMedium', t.headlineMedium),
      ('headlineSmall', t.headlineSmall),
      ('titleLarge', t.titleLarge),
      ('titleMedium', t.titleMedium),
      ('titleSmall', t.titleSmall),
      ('bodyLarge', t.bodyLarge),
      ('bodyMedium', t.bodyMedium),
      ('bodySmall', t.bodySmall),
      ('labelLarge', t.labelLarge),
      ('labelMedium', t.labelMedium),
      ('labelSmall', t.labelSmall),
    ];
    return _Section(
      title: 'Typography',
      note: 'Be Vietnam Pro. Every Vietnamese letter, with its marks, comes from this one font.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, style) in styles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name · ${style!.fontSize!.toStringAsFixed(0)}/${(style.fontSize! * style.height!).toStringAsFixed(0)}'
                    ' · w${style.fontWeight!.value}',
                    style: t.labelSmall,
                  ),
                  Text(_sample, style: style),
                ],
              ),
            ),
          Text('0:07 / 3:33 · 12 345', style: t.titleMedium?.copyWith(fontFeatures: AppTypography.tabularFigures)),
        ],
      ),
    );
  }
}

class _SpacingSection extends StatelessWidget {
  const _SpacingSection();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return _Section(
      title: 'Spacing',
      child: Column(
        children: [
          for (final value in AppSpacing.scale)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(width: 56, child: Text('${value.toStringAsFixed(0)} px', style: text.labelMedium)),
                  Container(
                    width: value,
                    height: 12,
                    decoration: BoxDecoration(color: c.accent, borderRadius: AppRadius.all(2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShapeSection extends StatelessWidget {
  const _ShapeSection();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    Widget box(String label, {double radius = AppRadius.md, List<BoxShadow>? shadow}) => Column(
          children: [
            Container(
              width: 96,
              height: 72,
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: AppRadius.all(radius),
                border: Border.all(color: c.outline),
                boxShadow: shadow,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: text.labelMedium),
          ],
        );
    return _Section(
      title: 'Radius and elevation',
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.lg,
        children: [
          box('xs 4', radius: AppRadius.xs),
          box('sm 8', radius: AppRadius.sm),
          box('md 12'),
          box('lg 16', radius: AppRadius.lg),
          box('xl 24', radius: AppRadius.xl),
          box('low', shadow: AppElevation.low(brightness)),
          box('medium', shadow: AppElevation.medium(brightness)),
          box('high', shadow: AppElevation.high(brightness)),
        ],
      ),
    );
  }
}

class _MotionSection extends StatefulWidget {
  const _MotionSection();

  @override
  State<_MotionSection> createState() => _MotionSectionState();
}

class _MotionSectionState extends State<_MotionSection> {
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final durations = {
      'fast ${AppDurations.fast.inMilliseconds} ms': AppDurations.fast,
      'normal ${AppDurations.normal.inMilliseconds} ms': AppDurations.normal,
      'slow ${AppDurations.slow.inMilliseconds} ms': AppDurations.slow,
    };
    return _Section(
      title: 'Motion',
      note: 'Press the button: the three dots travel with the three durations.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton(
            key: const Key('motionButton'),
            onPressed: () => setState(() => _moved = !_moved),
            child: const Text('Move'),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final entry in durations.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(entry.key, style: text.labelMedium)),
                  Expanded(
                    child: SizedBox(
                      height: 16,
                      child: AnimatedAlign(
                        duration: entry.value,
                        curve: AppCurves.standard,
                        alignment: _moved ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakpointSection extends StatelessWidget {
  const _BreakpointSection();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return _Section(
      title: 'Breakpoints',
      note: 'compact < ${AppBreakpoints.compact.toStringAsFixed(0)} ≤ medium < '
          '${AppBreakpoints.medium.toStringAsFixed(0)} ≤ expanded. Resize the window to see it change.',
      child: Text(
        'This window is ${width.toStringAsFixed(0)} px wide: ${context.screenSize.name}',
        key: const Key('screenSizeLabel'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ComponentsSection extends StatelessWidget {
  const _ComponentsSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Components',
      note: 'Material components in the LaSono theme. The app\'s own components are added as they are built.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Filled')),
              const FilledButton(onPressed: null, child: Text('Disabled')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              TextButton(onPressed: () {}, child: const Text('Text')),
              IconButton(onPressed: () {}, tooltip: 'Like', icon: const Icon(Icons.favorite_border)),
              const Chip(label: Text('Riêng tư')),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              SizedBox(
                width: 280,
                child: TextField(decoration: InputDecoration(labelText: 'Tiêu đề', hintText: 'Nắng ấm xa dần')),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: InputDecoration(labelText: 'Email', errorText: 'Email không hợp lệ'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Switch(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: Slider(value: 0.4, onChanged: (_) {})),
              const SizedBox(width: AppSpacing.lg),
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              for (var i = 0; i < AppGradients.cover.length; i++)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.all(AppRadius.md),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppGradients.cover[i].$1, AppGradients.cover[i].$2],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              OutlinedButton(
                key: const Key('openDialogButton'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Xoá bài hát?'),
                    content: const Text('Bài hát và âm thanh của nó sẽ bị xoá vĩnh viễn.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
                      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Xoá')),
                    ],
                  ),
                ),
                child: const Text('Dialog'),
              ),
              OutlinedButton(
                key: const Key('openSnackBarButton'),
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Đã lưu thay đổi'))),
                child: const Text('Snackbar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Starts the made-up tracks in the player bar, to try the bar and the queue.
class _PlayerSection extends StatelessWidget {
  const _PlayerSection();

  @override
  Widget build(BuildContext context) {
    final world = RepositoriesScope.maybeOf(context)?.fakeWorld;
    final playback = PlaybackScope.maybeOf(context);
    return _Section(
      title: 'Player bar',
      note: 'The bar at the bottom appears when something plays. The tracks here are made up; their sound is a short tune.',
      child: world == null || playback == null
          ? Text(
              'Not available here: the fake tracks need a debug build, or --dart-define=FAKE_SOCIAL=true.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                FilledButton.icon(
                  key: const Key('playFakeQueue'),
                  onPressed: () => playback.playQueue(world.tracks, sourceId: 'gallery'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play the 30 fake tracks'),
                ),
                OutlinedButton(
                  key: const Key('stopFakeQueue'),
                  onPressed: playback.stop,
                  child: const Text('Stop'),
                ),
              ],
            ),
    );
  }
}

/// The components of LaSono itself, made with made-up data. Each is also tried in tests; this page is to look at them.
class _AppComponentsSection extends StatefulWidget {
  const _AppComponentsSection();

  @override
  State<_AppComponentsSection> createState() => _AppComponentsSectionState();
}

class _AppComponentsSectionState extends State<_AppComponentsSection> {
  static const _viewer = 'gallery-viewer';

  // Used when the page is shown on its own (without the app around it).
  late final _world = FakeWorld();
  late final _behavior = FakeBehavior();
  late final _social = FakeSocialRepository(_world, _behavior, () => _viewer);
  late final _directory = UserDirectory(FakeUserRepository(_world, _behavior, () => _viewer));
  late final _waveforms = WaveformCache(FakeTrackRepository(_world, _behavior, () => _viewer));

  @override
  Widget build(BuildContext context) {
    final repositories = RepositoriesScope.maybeOf(context);
    final playback = PlaybackScope.maybeOf(context);
    final world = repositories?.fakeWorld ?? _world;
    final directory = repositories?.fakeWorld != null ? repositories!.directory : _directory;
    final waveforms = repositories?.fakeWorld != null ? repositories!.waveforms : _waveforms;
    final social = repositories?.fakeWorld != null ? repositories!.social : _social;
    final text = Theme.of(context).textTheme;

    final ready = world.tracks.where((t) => t.isReady).toList();
    // A track with plenty of comments, to see them on the waveform.
    final track = ready.firstWhere((t) => world.commentCountOf(t.id) >= 5, orElse: () => ready.first);
    final processing = world.tracks.firstWhere((t) => t.status == 'PROCESSING');
    final failed = world.tracks.firstWhere((t) => t.status == 'FAILED');
    final owner = world.user(track.ownerId)!;
    final markers = [
      for (final comment in world.commentsOf(track.id).take(10))
        WaveformMarker(
          id: comment.id,
          positionMs: comment.positionMs,
          authorId: comment.authorId,
          authorName: world.user(comment.authorId)?.displayName ?? '?',
          text: comment.text,
        ),
    ];
    Widget label(String value) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
          child: Text(value, style: text.titleMedium),
        );

    return _Section(
      title: 'App components',
      note: 'Made with the fake world. Hover the waveform, press a heart, follow a user.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Cover and avatar (colours made from the id)'),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in world.tracks.take(6)) CoverArt(trackId: t.id, size: 64),
              for (final u in world.users.take(6)) UserAvatar(userId: u.id, displayName: u.displayName, size: 44),
            ],
          ),
          label('Waveform with comments'),
          if (markers.isEmpty)
            const Text('No comment on this track.')
          else
            WaveformView(
              peaks: track.waveform ?? const [],
              progress: 0.3,
              durationMs: track.durationMs,
              markers: markers,
              onSeek: (_) {},
            ),
          label('Track cards: ready, processing, failed'),
          if (playback == null)
            Text('The cards need the player: open this page inside the app.', style: text.bodySmall)
          else
            for (final t in [ready[0], ready[1], processing, failed])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: TrackCard(
                  track: t,
                  playback: playback,
                  directory: directory,
                  waveforms: waveforms,
                  social: social,
                  viewerId: _viewer,
                  onPlay: () => playback.playQueue(ready, startIndex: ready.indexWhere((r) => r.id == t.id), sourceId: 'gallery'),
                  onOpen: () {},
                  onOpenUser: (_) {},
                  onNeedLogin: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onToggleVisibility: () {},
                ),
              ),
          label('Like and follow (try them: the fake network takes 200-600 ms)'),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LikeButton(trackId: track.id, liked: false, count: track.likeCount, social: social, signedIn: true, onNeedLogin: () {}),
              LikeButton(trackId: ready[1].id, liked: true, count: 1234, social: social, signedIn: true, onNeedLogin: () {}),
              FollowButton(userId: FakeWorld.userId(8), following: false, social: social, viewerId: _viewer, onNeedLogin: () {}),
              FollowButton(userId: FakeWorld.userId(1), following: true, social: social, viewerId: _viewer, onNeedLogin: () {}, compact: true),
            ],
          ),
          label('Comments'),
          CommentComposer(
            viewerId: _viewer,
            viewerName: 'Gallery',
            durationMs: track.durationMs,
            livePosition: null,
            onSubmit: (position, text) async => _social.postComment(track.id, positionMs: position, text: text),
            onNeedLogin: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          CommentList(
            comments: world.commentsOf(track.id).take(3).toList(),
            directory: directory,
            viewerId: _viewer,
            trackOwnerId: track.ownerId,
            onSeekTo: (_) {},
            onDelete: (_) async {},
          ),
          label('Users'),
          UserTile(profile: world.profileOf(owner), trailing: FollowButton(userId: owner.id, following: false, social: social, viewerId: _viewer, onNeedLogin: () {}, compact: true)),
          const SizedBox(height: AppSpacing.md),
          ProfileHeader(
            profile: Profile(userId: owner.id, displayName: owner.displayName, followerCount: world.followerCountOf(owner.id), followingCount: 12),
            trackCount: 14,
            action: FollowButton(userId: owner.id, following: false, social: social, viewerId: _viewer, onNeedLogin: () {}),
          ),
          label('Loading, empty, error'),
          const Row(
            children: [
              SkeletonLoader(height: 48, circle: true),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SkeletonLoader(width: 220), SizedBox(height: AppSpacing.sm), SkeletonLoader(width: 140, height: 12)])),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SizedBox(height: 300, child: EmptyState(icon: Icons.dynamic_feed_rounded, title: 'Bảng tin của bạn đang trống', message: 'Theo dõi vài người để xem bài mới của họ ở đây.')),
          SizedBox(height: 260, child: ErrorState(message: errorMessageFor(const Object()), onRetry: () {})),
        ],
      ),
    );
  }
}
