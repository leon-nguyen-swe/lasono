import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../data/repository_exception.dart';
import '../data/social_repository.dart';
import '../models/engagement.dart';
import 'states.dart';

/// "Theo dõi" for a user, which becomes "Đang theo dõi" (and "Bỏ theo dõi" under the pointer).
///
/// It works like the like button: a press changes the button at once, the server's answer confirms it, a failure
/// puts it back with a message, a second press while the first is on its way is ignored, and without a login a press
/// asks the user to log in. It is not shown at all for the logged-in user's own page: nobody follows themselves.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.userId,
    required this.following,
    required this.social,
    required this.viewerId,
    required this.onNeedLogin,
    this.onChanged,
    this.compact = false,
  });

  final String userId;
  final bool following;
  final SocialRepository social;

  /// The id of the logged-in user, or null when nobody is.
  final String? viewerId;
  final VoidCallback onNeedLogin;
  final ValueChanged<FollowState>? onChanged;

  /// A smaller button, for a row of a list.
  final bool compact;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _following = widget.following;
  bool _busy = false;
  bool _hover = false;

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && (oldWidget.userId != widget.userId || oldWidget.following != widget.following)) {
      _following = widget.following;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (widget.viewerId == null) {
      widget.onNeedLogin();
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final was = _following;
    setState(() {
      _busy = true;
      _following = !was;
    });
    try {
      final state = await (was ? widget.social.unfollowUser(widget.userId) : widget.social.followUser(widget.userId));
      if (!mounted) return;
      setState(() => _following = state.following);
      widget.onChanged?.call(state);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _following = was);
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
    if (widget.viewerId != null && widget.viewerId == widget.userId) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final size = widget.compact ? const Size(0, 36) : const Size(0, 44);
    final padding = EdgeInsets.symmetric(horizontal: widget.compact ? AppSpacing.md : AppSpacing.xl);
    // A row of a list is lower than a button of a page; the normal one keeps the full 48 px touch area.
    final tapTarget = widget.compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded;

    final Widget button;
    if (_following) {
      final label = _hover ? 'Bỏ theo dõi' : 'Đang theo dõi';
      button = OutlinedButton.icon(
        key: const Key('followButton'),
        onPressed: _toggle,
        style: OutlinedButton.styleFrom(minimumSize: size, padding: padding, foregroundColor: _hover ? c.error : c.textPrimary, tapTargetSize: tapTarget),
        icon: Icon(_hover ? Icons.person_remove_alt_1_outlined : Icons.check_rounded, size: 18),
        label: Text(label),
      );
    } else {
      button = FilledButton.icon(
        key: const Key('followButton'),
        onPressed: _toggle,
        style: FilledButton.styleFrom(minimumSize: size, padding: padding, tapTargetSize: tapTarget),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: const Text('Theo dõi'),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        toggled: _following,
        label: _following ? 'Đang theo dõi' : 'Theo dõi',
        child: ExcludeSemantics(child: button),
      ),
    );
  }
}
