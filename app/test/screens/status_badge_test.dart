import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/screens/status_badge.dart';

Future<void> _pump(WidgetTester tester, String status) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StatusBadge(status: status))),
    );

Color? _textColor(WidgetTester tester, String status) =>
    tester.widget<Text>(find.text(status)).style?.color;

void main() {
  testWidgets('shows the status', (WidgetTester tester) async {
    await _pump(tester, 'READY');

    expect(find.text('READY'), findsOneWidget);
  });

  testWidgets('shows a spinner only while the track is processing',
      (WidgetTester tester) async {
    await _pump(tester, 'PROCESSING');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(tester, 'READY');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await _pump(tester, 'FAILED');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows a failed track in the error colour',
      (WidgetTester tester) async {
    await _pump(tester, 'FAILED');
    final errorColor = Theme.of(tester.element(find.byType(StatusBadge)))
        .colorScheme
        .error;

    expect(_textColor(tester, 'FAILED'), errorColor);

    await _pump(tester, 'READY');
    expect(_textColor(tester, 'READY'), isNot(errorColor));
  });
}
