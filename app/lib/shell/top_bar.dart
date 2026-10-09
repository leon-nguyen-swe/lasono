import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../core/theme/theme.dart';
import '../widgets/user_avatar.dart';

/// The name of the app: five bars like a waveform, then "LaSono". Not the logo, colours or shapes of any other service.
class LaSonoLogo extends StatelessWidget {
  const LaSonoLogo({super.key, this.compact = false});

  /// Without the word, only the bars.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    const heights = [0.45, 0.8, 1.0, 0.65, 0.35];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final h in heights)
                Container(
                  width: 3.5,
                  height: 24 * h,
                  decoration: BoxDecoration(color: c.accent, borderRadius: AppRadius.all(2)),
                ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'La', style: TextStyle(color: c.textPrimary)),
                TextSpan(text: 'Sono', style: TextStyle(color: c.accent)),
              ],
            ),
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
        ],
      ],
    );
  }
}

/// The bar at the top of every page: the logo, Home and Feed, a big search field, Upload and the account.
/// It does not know about the router: what a press does is given by the callbacks.
class TopBar extends StatefulWidget {
  const TopBar({
    super.key,
    required this.session,
    required this.themeController,
    required this.location,
    required this.searchQuery,
    required this.onHome,
    required this.onFeed,
    required this.onUpload,
    required this.onSearch,
    required this.onLogin,
    required this.onRegister,
    required this.onProfile,
    required this.onLogout,
  });

  final SessionController session;
  final ThemeController themeController;

  /// The path of the page shown, to mark Home or Feed as the current one.
  final String location;

  /// What the search page is showing, or null when it is not on that page.
  final String? searchQuery;

  final VoidCallback onHome;
  final VoidCallback onFeed;
  final VoidCallback onUpload;

  /// A search was typed (after a short pause) or sent with Enter. An empty text opens the search page.
  final ValueChanged<String> onSearch;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final ValueChanged<String> onProfile;
  final VoidCallback onLogout;

  /// How long the user must stop typing before the search runs.
  static const searchPause = Duration(milliseconds: 400);

  /// The narrowest window that has room for the whole bar (two words, a search field, Upload, and two account
  /// buttons). Below it the bar uses icons, which fit all the way down to a phone.
  static const fullBarMinWidth = 900.0;

  @override
  State<TopBar> createState() => _TopBarState();
}

enum _MenuAction { profile, theme, logout }

class _TopBarState extends State<TopBar> {
  late final TextEditingController _search = TextEditingController(text: widget.searchQuery ?? '');
  Timer? _pause;

  @override
  void didUpdateWidget(TopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page was opened with a text (a link): show it in the field. And leaving the search page empties the field.
    final shown = widget.searchQuery;
    if (shown != null && shown != _search.text.trim()) {
      _search.text = shown;
    } else if (shown == null && oldWidget.searchQuery != null) {
      _search.clear();
    }
  }

  @override
  void dispose() {
    _pause?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _pause?.cancel();
    final query = text.trim();
    if (query.length < 2) return;
    _pause = Timer(TopBar.searchPause, () => widget.onSearch(query));
  }

  void _submitted(String text) {
    _pause?.cancel();
    widget.onSearch(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final size = context.screenSize;
    final c = AppColors.of(context);
    return Material(
      color: c.background,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.outline))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: size == ScreenSize.compact ? 56 : 64,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size == ScreenSize.compact ? AppSpacing.md : AppSpacing.xl),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([widget.session, widget.themeController]),
                    builder: (context, _) =>
                        MediaQuery.sizeOf(context).width < TopBar.fullBarMinWidth ? _compact(context) : _wide(context, size),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _onHome => widget.location == '/';
  bool get _onFeed => widget.location.startsWith('/feed');

  Widget _logo() => InkWell(
        key: const Key('logo'),
        borderRadius: AppRadius.all(AppRadius.sm),
        onTap: widget.onHome,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: LaSonoLogo(compact: context.screenSize == ScreenSize.compact),
        ),
      );

  Widget _wide(BuildContext context, ScreenSize size) {
    return Row(
      children: [
        _logo(),
        const SizedBox(width: AppSpacing.lg),
        _NavItem(key: const Key('navHome'), label: 'Trang chủ', icon: Icons.home_rounded, active: _onHome, onTap: widget.onHome),
        const SizedBox(width: AppSpacing.xs),
        _NavItem(key: const Key('navFeed'), label: 'Bảng tin', icon: Icons.dynamic_feed_rounded, active: _onFeed, onTap: widget.onFeed),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _searchField()))),
        const SizedBox(width: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('uploadButton'),
          onPressed: widget.onUpload,
          icon: const Icon(Icons.file_upload_outlined, size: 20),
          label: const Text('Tải lên'),
        ),
        const SizedBox(width: AppSpacing.md),
        ..._account(context),
      ],
    );
  }

  Widget _compact(BuildContext context) {
    // Home is the logo, so there is no Home icon: the row has to fit 320 px.
    const tight = VisualDensity.compact;
    return Row(
      children: [
        _logo(),
        const Spacer(),
        IconButton(key: const Key('navFeed'), visualDensity: tight, tooltip: 'Bảng tin', isSelected: _onFeed, onPressed: widget.onFeed, icon: const Icon(Icons.dynamic_feed_rounded)),
        IconButton(key: const Key('searchIcon'), visualDensity: tight, tooltip: 'Tìm kiếm', onPressed: () => widget.onSearch(''), icon: const Icon(Icons.search_rounded)),
        IconButton(key: const Key('uploadIcon'), visualDensity: tight, tooltip: 'Tải lên', onPressed: widget.onUpload, icon: const Icon(Icons.file_upload_outlined)),
        const SizedBox(width: AppSpacing.xs),
        ..._account(context, compact: true),
      ],
    );
  }

  Widget _searchField() {
    final c = AppColors.of(context);
    return TextField(
      key: const Key('searchField'),
      controller: _search,
      textInputAction: TextInputAction.search,
      onChanged: _typed,
      onSubmitted: _submitted,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Tìm bài hát, nghệ sĩ…',
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        fillColor: c.surfaceRaised,
        border: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.pill), borderSide: BorderSide(color: c.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.pill), borderSide: BorderSide(color: c.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.all(AppRadius.pill), borderSide: BorderSide(color: c.accent, width: 2)),
      ),
    );
  }

  List<Widget> _account(BuildContext context, {bool compact = false}) {
    final session = widget.session;
    final account = session.account;
    if (session.status == SessionStatus.signedIn && account != null) {
      return [
        PopupMenuButton<_MenuAction>(
          key: const Key('accountMenu'),
          tooltip: 'Tài khoản',
          offset: const Offset(0, 48),
          onSelected: (action) => switch (action) {
            _MenuAction.profile => widget.onProfile(account.userId),
            _MenuAction.theme => widget.themeController.toggle(),
            _MenuAction.logout => widget.onLogout(),
          },
          itemBuilder: (_) => [
            PopupMenuItem<_MenuAction>(
              enabled: false,
              child: Text(account.displayName, style: Theme.of(context).textTheme.titleSmall),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(key: Key('profileAction'), value: _MenuAction.profile, child: Text('Trang cá nhân')),
            PopupMenuItem(
              key: const Key('themeAction'),
              value: _MenuAction.theme,
              child: Text(widget.themeController.mode == ThemeMode.light ? 'Giao diện tối' : 'Giao diện sáng'),
            ),
            const PopupMenuItem(key: Key('logoutAction'), value: _MenuAction.logout, child: Text('Đăng xuất')),
          ],
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: UserAvatar(userId: account.userId, displayName: account.displayName, size: 36),
          ),
        ),
      ];
    }
    if (session.status == SessionStatus.restoring) {
      // The answer is not known yet: a grey circle in the place of the avatar, so nothing jumps when it arrives.
      return [
        Container(
          key: const Key('accountPlaceholder'),
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.of(context).surfaceHigh, shape: BoxShape.circle),
        ),
      ];
    }
    return [
      TextButton(
        key: const Key('loginButton'),
        onPressed: widget.onLogin,
        style: compact ? TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm)) : null,
        child: const Text('Đăng nhập'),
      ),
      if (!compact) ...[
        const SizedBox(width: AppSpacing.xs),
        OutlinedButton(key: const Key('registerButton'), onPressed: widget.onRegister, child: const Text('Tạo tài khoản')),
      ],
    ];
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.label, required this.icon, required this.active, required this.onTap});

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final colour = active ? c.accent : c.textSecondary;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active ? c.accentSoft : Colors.transparent,
            borderRadius: AppRadius.all(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: colour),
              const SizedBox(width: AppSpacing.xs),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colour)),
            ],
          ),
        ),
      ),
    );
  }
}
