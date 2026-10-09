import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import '../data/repository_exception.dart';
import '../data/social_repository.dart';
import '../models/engagement.dart';
import 'states.dart';

/// The heart and the number of likes of a track.
///
/// A press changes the heart and the number **at once** (the user does not wait for the server), and the server's
/// answer then confirms the state and the exact count. If the server refuses or cannot be reached, the heart goes
/// back to where it was and a message says why. A second press while the first is still on its way is ignored, so
/// a quick double press cannot send two contrary requests. Without a login, a press asks the user to log in.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.trackId,
    required this.liked,
    required this.count,
    required this.social,
    required this.signedIn,
    required this.onNeedLogin,
    this.onChanged,
    this.showCount = true,
    this.iconSize = 22,
  });

  final String trackId;
  final bool liked;
  final int count;
  final SocialRepository social;
  final bool signedIn;

  /// Called when a login is needed: the user is not logged in, or the login ran out.
  final VoidCallback onNeedLogin;

  /// Called with the state the server confirmed, so the screen can keep its copy of the track up to date.
  final ValueChanged<LikeState>? onChanged;

  final bool showCount;
  final double iconSize;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  late bool _liked = widget.liked;
  late int _count = widget.count;
  bool _busy = false;

  @override
  void didUpdateWidget(LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // What the screen says wins, unless a request of ours is still on its way (its answer will set the state).
    final changed = oldWidget.trackId != widget.trackId || oldWidget.liked != widget.liked || oldWidget.count != widget.count;
    if (changed && !_busy) {
      _liked = widget.liked;
      _count = widget.count;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (!widget.signedIn) {
      widget.onNeedLogin();
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final wasLiked = _liked;
    final wasCount = _count;
    setState(() {
      _busy = true;
      _liked = !wasLiked;
      _count = wasLiked ? math.max(0, wasCount - 1) : wasCount + 1;
    });
    try {
      final state = await (wasLiked ? widget.social.unlikeTrack(widget.trackId) : widget.social.likeTrack(widget.trackId));
      if (!mounted) return;
      setState(() {
        _liked = state.liked;
        _count = state.likeCount;
      });
      widget.onChanged?.call(state);
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _count = wasCount;
        });
      }
      if (e.needsLogin) {
        if (mounted) widget.onNeedLogin();
      } else if (messenger != null) {
        showToastOn(messenger, errorMessageFor(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final colour = _liked ? c.accent : c.textSecondary;
    return Semantics(
      button: true,
      toggled: _liked,
      label: _liked ? 'Bỏ thích' : 'Thích',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('likeButton'),
        borderRadius: AppRadius.all(AppRadius.pill),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The heart pops a little each time it is filled.
              TweenAnimationBuilder<double>(
                key: ValueKey(_liked),
                tween: Tween(begin: _liked ? 0.7 : 1, end: 1),
                duration: AppDurations.normal,
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Icon(
                  _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: Key(_liked ? 'likedIcon' : 'unlikedIcon'),
                  size: widget.iconSize,
                  color: colour,
                ),
              ),
              if (widget.showCount) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  formatCount(_count),
                  key: const Key('likeCount'),
                  style: text.labelLarge?.copyWith(color: colour, fontFeatures: AppTypography.tabularFigures),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
