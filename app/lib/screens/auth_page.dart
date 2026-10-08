import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../auth/session_controller.dart';
import '../core/theme/theme.dart';
import '../shell/top_bar.dart';

/// The field a message from the server is about.
enum AuthField { email, displayName, password, form }

/// Turns what the auth API says (English, from the server or from the app) into Vietnamese and says which field it is
/// about, so it can be shown under that field. A message the app does not know stays as it is, on the form.
({AuthField field, String text}) describeAuthError(String message) {
  const known = <String, (AuthField, String)>{
    'Wrong email or password': (AuthField.form, 'Email hoặc mật khẩu không đúng.'),
    'This email is already registered': (AuthField.email, 'Email này đã được đăng ký. Hãy đăng nhập.'),
    'Cannot reach the server': (AuthField.form, 'Không kết nối được tới máy chủ. Kiểm tra mạng rồi thử lại.'),
    'Request timed out': (AuthField.form, 'Máy chủ phản hồi quá chậm. Hãy thử lại.'),
    'Invalid details': (AuthField.form, 'Thông tin chưa hợp lệ. Hãy kiểm tra lại.'),
    'Invalid login': (AuthField.form, 'Thông tin chưa hợp lệ. Hãy kiểm tra lại.'),
    'Email is not valid': (AuthField.email, 'Email không hợp lệ.'),
    'Email must not be null': (AuthField.email, 'Hãy nhập email.'),
    'Display name must not be blank': (AuthField.displayName, 'Hãy nhập tên hiển thị.'),
    'Display name must not be null': (AuthField.displayName, 'Hãy nhập tên hiển thị.'),
    'Password must not be blank': (AuthField.password, 'Hãy nhập mật khẩu.'),
  };
  final exact = known[message];
  if (exact != null) return (field: exact.$1, text: exact.$2);

  // "Email must be at most 254 characters", "Display name must be at most 50 characters", "Password must be at least 8 ...".
  final atMost = RegExp(r'must be at most (\d+) (characters|bytes)').firstMatch(message);
  final atLeast = RegExp(r'must be at least (\d+) characters').firstMatch(message);
  if (message.startsWith('Email')) {
    return (field: AuthField.email, text: atMost != null ? 'Email tối đa ${atMost[1]} ký tự.' : 'Email không hợp lệ.');
  }
  if (message.startsWith('Display name')) {
    return (field: AuthField.displayName, text: atMost != null ? 'Tên hiển thị tối đa ${atMost[1]} ký tự.' : 'Tên hiển thị không hợp lệ.');
  }
  if (message.startsWith('Password')) {
    if (atLeast != null) return (field: AuthField.password, text: 'Mật khẩu cần ít nhất ${atLeast[1]} ký tự.');
    if (atMost != null) return (field: AuthField.password, text: 'Mật khẩu quá dài (tối đa ${atMost[1]} byte).');
    return (field: AuthField.password, text: 'Mật khẩu không hợp lệ.');
  }
  if (message.startsWith('Server error')) {
    return (field: AuthField.form, text: 'Máy chủ đang gặp sự cố. Hãy thử lại sau một lúc.');
  }
  return (field: AuthField.form, text: message);
}

/// Log in and create an account, on one page that has two modes. On a wide window the left half says what LaSono is and
/// the right half is the form; on a phone there is only the form. Errors from the server appear under the field they are
/// about. After a login the user goes back to where they were ([from]).
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.session, this.registering = false, this.from});

  final SessionController session;

  /// Opens on "Tạo tài khoản" instead of "Đăng nhập".
  final bool registering;

  /// The place to go back to after the login; null for the home page.
  final String? from;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  final _errors = <AuthField, String>{};

  bool get _registering => widget.registering;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode() {
    final target = _registering ? '/login' : '/register';
    final from = widget.from;
    context.go(from == null ? target : '$target?from=${Uri.encodeQueryComponent(from)}');
  }

  // What can be seen wrong without asking the server. The server has the last word (it also checks the details).
  Map<AuthField, String> _checkHere() {
    final problems = <AuthField, String>{};
    final email = _email.text.trim();
    if (email.isEmpty) {
      problems[AuthField.email] = 'Hãy nhập email.';
    } else if (_registering && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      problems[AuthField.email] = 'Email không hợp lệ.';
    }
    if (_registering && _name.text.trim().isEmpty) problems[AuthField.displayName] = 'Hãy nhập tên hiển thị.';
    if (_password.text.isEmpty) {
      problems[AuthField.password] = 'Hãy nhập mật khẩu.';
    } else if (_registering && _password.text.length < 8) {
      problems[AuthField.password] = 'Mật khẩu cần ít nhất 8 ký tự.';
    }
    return problems;
  }

  Future<void> _submit() async {
    // Set before the first await, so a second press while the request runs finds the form busy and does nothing.
    if (_busy) return;
    final problems = _checkHere();
    if (problems.isNotEmpty) {
      setState(() => _errors
        ..clear()
        ..addAll(problems));
      return;
    }
    setState(() {
      _busy = true;
      _errors.clear();
    });
    try {
      if (_registering) {
        await widget.session.register(email: _email.text.trim(), displayName: _name.text.trim(), password: _password.text);
      } else {
        await widget.session.login(email: _email.text.trim(), password: _password.text);
      }
      if (mounted) context.go(_safeFrom() ?? '/');
    } on AuthApiException catch (e) {
      final described = describeAuthError(e.message);
      if (mounted) setState(() => _errors[described.field] = described.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _safeFrom() {
    final from = widget.from;
    return from != null && from.startsWith('/') && !from.startsWith('//') ? from : null;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final c = AppColors.of(context);
    final form = _form(context);
    return Scaffold(
      backgroundColor: c.background,
      body: wide
          ? Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(flex: 6, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpacing.xxl), child: form))),
              ],
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LaSonoLogo(),
                      const SizedBox(height: AppSpacing.xxl),
                      form,
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_registering ? 'Tạo tài khoản' : 'Chào mừng trở lại', key: const Key('authTitle'), style: text.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _registering ? 'Miễn phí và chỉ mất một phút.' : 'Đăng nhập để tải nhạc lên, thích và bình luận.',
              style: text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              key: const Key('emailField'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: 'Email', errorText: _errors[AuthField.email]),
            ),
            if (_registering) ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('displayNameField'),
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.nickname],
                decoration: InputDecoration(labelText: 'Tên hiển thị', errorText: _errors[AuthField.displayName]),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('passwordField'),
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [_registering ? AutofillHints.newPassword : AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                helperText: _registering ? 'Ít nhất 8 ký tự.' : null,
                errorText: _errors[AuthField.password],
                suffixIcon: IconButton(
                  key: const Key('togglePassword'),
                  tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
            ),
            if (_errors[AuthField.form] != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const Key('formError'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: c.error.withValues(alpha: 0.12), borderRadius: AppRadius.all(AppRadius.md)),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 20, color: c.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(_errors[AuthField.form]!, style: text.bodySmall?.copyWith(color: c.textPrimary))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const Key('submitButton'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onAccent))
                  : Text(_registering ? 'Tạo tài khoản' : 'Đăng nhập'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_registering ? 'Đã có tài khoản?' : 'Chưa có tài khoản?', style: text.bodyMedium?.copyWith(color: c.textSecondary)),
                TextButton(
                  key: const Key('switchModeButton'),
                  onPressed: _busy ? null : _switchMode,
                  child: Text(_registering ? 'Đăng nhập' : 'Đăng ký'),
                ),
              ],
            ),
            Center(
              child: TextButton(
                key: const Key('backHome'),
                onPressed: () => context.go('/'),
                child: const Text('Về trang chủ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The left half of the login page on a wide window: what LaSono is, in the colours of the app.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (from, to) = AppGradients.cover[5];
    const light = Colors.white;
    Widget point(IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: light.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: light, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(label, style: text.bodyLarge?.copyWith(color: light))),
            ],
          ),
        );
    return Container(
      key: const Key('brandPanel'),
      padding: const EdgeInsets.all(AppSpacing.huge),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq_rounded, color: light, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Text('LaSono', style: text.displaySmall?.copyWith(color: light)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Nghe, chia sẻ và khám phá âm nhạc.', style: text.headlineMedium?.copyWith(color: light)),
          const SizedBox(height: AppSpacing.xxl),
          point(Icons.cloud_upload_outlined, 'Tải nhạc của bạn lên và nghe ngay'),
          point(Icons.mode_comment_outlined, 'Bình luận trực tiếp trên sóng âm, đúng giây bạn thích'),
          point(Icons.people_outline_rounded, 'Theo dõi nghệ sĩ và xem bài mới của họ'),
        ],
      ),
    );
  }
}
