import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../data/repository_exception.dart';

/// What to tell the user about a failure, in Vietnamese, from the kind of failure. The reason a server gave for
/// refusing a request (`invalid`) is kept as it is, because it says what to correct.
String errorMessageFor(Object error) {
  if (error is! RepositoryException) return 'Đã có lỗi xảy ra. Hãy thử lại.';
  return switch (error.kind) {
    RepositoryErrorKind.network => 'Không kết nối được tới máy chủ. Kiểm tra mạng rồi thử lại.',
    RepositoryErrorKind.unauthorized => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
    RepositoryErrorKind.forbidden => 'Bạn không có quyền làm việc này.',
    RepositoryErrorKind.notFound => 'Không tìm thấy. Có thể nó đã bị xoá.',
    RepositoryErrorKind.conflict => 'Hiện chưa làm được việc này (bài hát có thể chưa xử lý xong). Hãy thử lại sau.',
    RepositoryErrorKind.invalid => error.message,
    RepositoryErrorKind.server => 'Máy chủ đang gặp sự cố. Hãy thử lại sau một lúc.',
    RepositoryErrorKind.other => 'Đã có lỗi xảy ra. Hãy thử lại.',
  };
}

/// A grey block that shimmers, in the place of something that is still loading. With "reduce motion" on (an
/// accessibility setting) it does not move.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.width, this.height = 16, this.radius = AppRadius.sm, this.circle = false});

  final double? width;
  final double height;
  final double radius;

  /// A round block (the place of an avatar); [height] is then the diameter.
  final bool circle;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: 'Đang tải',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 3 - 1; // the light band travels from the left of the block to its right
          return Container(
            key: const Key('skeleton'),
            width: widget.circle ? widget.height : widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: widget.circle ? null : AppRadius.all(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(t - 1, 0),
                end: Alignment(t + 1, 0),
                colors: [c.surfaceRaised, c.surfaceHigh, c.surfaceRaised],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A list or a page that has nothing in it: what it is, and what to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;

  /// A button that leads somewhere useful (for example "Khám phá").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: c.accent),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(message!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: c.textSecondary)),
              ],
              if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A failure, with a button to try again.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.compact = false});

  /// The message for any error caught from a repository (see [errorMessageFor]).
  factory ErrorState.from(Object error, {Key? key, VoidCallback? onRetry, bool compact = false}) =>
      ErrorState(key: key, message: errorMessageFor(error), onRetry: onRetry, compact: compact);

  final String message;
  final VoidCallback? onRetry;

  /// Smaller, in a line (for the end of a list that could not load its next page).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final retry = onRetry == null
        ? null
        : (compact
            ? TextButton(key: const Key('retryButton'), onPressed: onRetry, child: const Text('Thử lại'))
            : FilledButton.icon(
                key: const Key('retryButton'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Thử lại'),
              ));
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: c.error),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(message, style: text.bodySmall?.copyWith(color: c.error))),
            if (retry != null) ...[const SizedBox(width: AppSpacing.sm), retry],
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: c.error),
              const SizedBox(height: AppSpacing.md),
              Text(message, textAlign: TextAlign.center, style: text.bodyMedium),
              if (retry != null) ...[const SizedBox(height: AppSpacing.lg), retry],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks the user to confirm something. True when they do; false when they cancel or close the box.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Xác nhận',
  String cancelLabel = 'Huỷ',
  bool destructive = false,
}) async {
  final c = AppColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(key: const Key('cancelButton'), onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        FilledButton(
          key: const Key('confirmButton'),
          style: destructive ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: Theme.of(context).colorScheme.onError) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A short message at the bottom of the screen, which goes away by itself.
void showToast(BuildContext context, String message, {bool error = false}) =>
    showToastOn(ScaffoldMessenger.of(context), message, error: error);

/// Like [showToast], on a messenger taken earlier: a button that was removed while its request ran can still tell
/// the user what went wrong.
void showToastOn(ScaffoldMessengerState messenger, String message, {bool error = false}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('toast'),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(AppSpacing.lg),
        content: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
