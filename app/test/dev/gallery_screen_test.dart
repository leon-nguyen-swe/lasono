import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/dev/gallery_screen.dart';

Widget _app(ThemeController controller) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: controller.mode,
        home: GalleryScreen(themeController: controller),
      ),
    );

// The page has a progress spinner, which animates for ever, so pumpAndSettle would never return.
const _settle = Duration(milliseconds: 500);

// A change of theme is animated from the frame that builds it, so one frame builds and a second one finishes it.
Future<void> _settleTheme(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(_settle);
}

void main() {
  testWidgets('shows the tokens and the components in the dark theme without errors', (tester) async {
    tester.view.physicalSize = const Size(1280, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ThemeController()));

    expect(find.text('Colours'), findsOneWidget);
    expect(find.text('Typography'), findsOneWidget);
    expect(find.text('Components'), findsOneWidget);
    // Vietnamese sample text is on the page.
    expect(find.textContaining('Nắng ấm xa dần'), findsWidgets);
    expect(tester.takeException(), isNull);

    // The made-up network answers after 200-600 ms; let it finish so no timer is left over.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the switch changes the theme to light and back', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ThemeController();

    await tester.pumpWidget(_app(controller));
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('lightModeSwitch')));
    await _settleTheme(tester);
    expect(controller.mode, ThemeMode.light);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.light);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('lightModeSwitch')));
    await _settleTheme(tester);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
  });

  testWidgets('tells which breakpoint the window is in', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final (width, name) in [(400.0, 'compact'), (800.0, 'medium'), (1400.0, 'expanded')]) {
      // Tall enough that the whole page is built, so the label is there without scrolling to it.
      tester.view.physicalSize = Size(width, 9000);
      await tester.pumpWidget(_app(ThemeController()));
      await tester.pump(_settle);
      expect((tester.widget<Text>(find.byKey(const Key('screenSizeLabel')))).data, endsWith(name));
    }
  });

  testWidgets('the dialog and the snackbar open in the theme', (tester) async {
    tester.view.physicalSize = const Size(1280, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(ThemeController()));

    await tester.tap(find.byKey(const Key('openDialogButton')));
    await _settleTheme(tester);
    expect(find.text('Xoá bài hát?'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await _settleTheme(tester);

    await tester.tap(find.byKey(const Key('openSnackBarButton')));
    await tester.pump();
    expect(find.text('Đã lưu thay đổi'), findsOneWidget);
  });
}
