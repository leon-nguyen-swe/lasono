import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/widgets/states.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('errorMessageFor', () {
    String say(RepositoryErrorKind kind, [String message = 'x']) => errorMessageFor(RepositoryException(message, kind: kind));

    test('says something useful in Vietnamese for every kind of failure', () {
      for (final kind in RepositoryErrorKind.values) {
        expect(say(kind), isNotEmpty);
      }
      expect(say(RepositoryErrorKind.network), contains('kết nối'));
      expect(say(RepositoryErrorKind.unauthorized), contains('đăng nhập'));
      expect(say(RepositoryErrorKind.forbidden), contains('quyền'));
      expect(say(RepositoryErrorKind.notFound), contains('Không tìm thấy'));
    });

    test('keeps the reason the server gave for a request it refused, because it says what to correct', () {
      expect(say(RepositoryErrorKind.invalid, 'positionMs must be between 0 and 213400'), 'positionMs must be between 0 and 213400');
    });

    test('does not show the technical message of the other kinds', () {
      expect(say(RepositoryErrorKind.server, 'Server error (500)'), isNot(contains('500')));
      expect(say(RepositoryErrorKind.network, 'SocketException'), isNot(contains('Socket')));
    });

    test('an error that is not a RepositoryException still gets a message', () {
      expect(errorMessageFor(StateError('boom')), contains('lỗi'));
    });
  });

  group('SkeletonLoader', () {
    testWidgets('has the asked size and shimmers', (tester) async {
      await tester.pumpWidget(_app(const Center(child: SkeletonLoader(width: 120, height: 20))));
      expect(tester.getSize(find.byKey(const Key('skeleton'))), const Size(120, 20));

      final before = tester.widget<Container>(find.byKey(const Key('skeleton'))).decoration! as BoxDecoration;
      await tester.pump(const Duration(milliseconds: 500));
      final after = tester.widget<Container>(find.byKey(const Key('skeleton'))).decoration! as BoxDecoration;

      expect((before.gradient! as LinearGradient).begin, isNot((after.gradient! as LinearGradient).begin));
    });

    testWidgets('does not move when the user asked for less motion, so pumpAndSettle can finish', (tester) async {
      await tester.pumpWidget(_app(const Center(child: SkeletonLoader(width: 120)), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skeleton')), findsOneWidget);
    });

    testWidgets('can be round, for the place of an avatar', (tester) async {
      await tester.pumpWidget(_app(const Center(child: SkeletonLoader(height: 40, circle: true)), reduceMotion: true));
      expect(tester.getSize(find.byKey(const Key('skeleton'))), const Size(40, 40));
      final decoration = tester.widget<Container>(find.byKey(const Key('skeleton'))).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('is announced as loading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const Center(child: SkeletonLoader(width: 50)), reduceMotion: true));
      expect(find.bySemanticsLabel('Đang tải'), findsOneWidget);
      handle.dispose();
    });
  });

  group('EmptyState', () {
    testWidgets('shows what is missing, why, and a way forward', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_app(EmptyState(
        icon: Icons.dynamic_feed_rounded,
        title: 'Bảng tin của bạn đang trống',
        message: 'Theo dõi vài người để xem bài mới của họ ở đây.',
        action: FilledButton(onPressed: () => pressed = true, child: const Text('Khám phá')),
      )));

      expect(find.text('Bảng tin của bạn đang trống'), findsOneWidget);
      expect(find.text('Theo dõi vài người để xem bài mới của họ ở đây.'), findsOneWidget);
      await tester.tap(find.text('Khám phá'));
      expect(pressed, isTrue);
    });

    testWidgets('works with only a title', (tester) async {
      await tester.pumpWidget(_app(const EmptyState(icon: Icons.search_off_rounded, title: 'Không có kết quả')));
      expect(find.text('Không có kết quả'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ErrorState', () {
    testWidgets('shows the message and a retry button that retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_app(ErrorState(message: 'Không kết nối được', onRetry: () => retries++)));

      expect(find.text('Không kết nối được'), findsOneWidget);
      await tester.tap(find.byKey(const Key('retryButton')));
      expect(retries, 1);
    });

    testWidgets('built from an exception, it says what the kind of failure means', (tester) async {
      await tester.pumpWidget(_app(ErrorState.from(const RepositoryException('x', kind: RepositoryErrorKind.network))));
      expect(find.textContaining('kết nối'), findsOneWidget);
      expect(find.byKey(const Key('retryButton')), findsNothing, reason: 'no way to retry was given');
    });

    testWidgets('the compact one fits in a line and also retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_app(ErrorState(message: 'Không tải thêm được', compact: true, onRetry: () => retries++)));
      await tester.tap(find.byKey(const Key('retryButton')));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('showConfirmDialog', () {
    Future<bool?> open(WidgetTester tester, {bool destructive = false}) async {
      bool? answer;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async => answer = await showConfirmDialog(
              context,
              title: 'Xoá bài hát?',
              message: 'Bài hát sẽ bị xoá vĩnh viễn.',
              confirmLabel: 'Xoá',
              destructive: destructive,
            ),
            child: const Text('mở'),
          ),
        ),
      )));
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('gives true when the user confirms', (tester) async {
      await open(tester);
      expect(find.text('Xoá bài hát?'), findsOneWidget);
      expect(find.text('Bài hát sẽ bị xoá vĩnh viễn.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmButton')));
      await tester.pumpAndSettle();
      expect(find.text('Xoá bài hát?'), findsNothing);
    });

    testWidgets('gives false on cancel, and false when the box is closed by pressing outside it', (tester) async {
      bool? first;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async => first = await showConfirmDialog(context, title: 't', message: 'm'),
            child: const Text('mở'),
          ),
        ),
      )));

      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelButton')));
      await tester.pumpAndSettle();
      expect(first, isFalse);

      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // the dark area outside the box
      await tester.pumpAndSettle();
      expect(first, isFalse);
    });

    testWidgets('a destructive confirmation is drawn in the colour of an error', (tester) async {
      await open(tester, destructive: true);
      final button = tester.widget<FilledButton>(find.byKey(const Key('confirmButton')));
      expect(button.style!.backgroundColor!.resolve({}), AppColors.dark.error);
    });
  });

  group('showToast', () {
    testWidgets('shows the message at the bottom, and a new one replaces the one before', (tester) async {
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: () => showToast(context, 'Đã lưu'), child: const Text('a')),
            FilledButton(onPressed: () => showToast(context, 'Lỗi rồi', error: true), child: const Text('b')),
          ]),
        ),
      )));

      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đã lưu'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

      await tester.tap(find.text('b'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Lỗi rồi'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Đã lưu'), findsNothing);
    });
  });
}
