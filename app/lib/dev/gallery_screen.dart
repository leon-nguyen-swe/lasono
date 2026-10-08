import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../data/app_repositories.dart';
import '../playback/playback_controller.dart';
import '../screens/status_badge.dart';
import '../screens/waveform_view.dart';

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
    _ComponentsSection(),
    _PlayerSection(),
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
    final c = AppColors.of(context);
    final peaks = [for (var i = 0; i < 120; i++) 0.15 + 0.8 * ((i * 37) % 100) / 100];
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
              const StatusBadge(status: 'PROCESSING'),
              const StatusBadge(status: 'READY'),
              const StatusBadge(status: 'FAILED'),
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
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadius.all(AppRadius.lg),
              border: Border.all(color: c.outline),
            ),
            child: WaveformView(peaks: peaks, progress: 0.35, onSeek: (_) {}, height: 72),
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
