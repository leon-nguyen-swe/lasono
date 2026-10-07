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

  // A still icon, not a spinner: a spinner animates forever, which tires the eye in a long list
  // and keeps widget tests from ever settling.
  testWidgets('shows an hourglass only while the track is processing',
      (WidgetTester tester) async {
    await _pump(tester, 'PROCESSING');
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

    await _pump(tester, 'READY');
    expect(find.byIcon(Icons.hourglass_top), findsNothing);

    await _pump(tester, 'FAILED');
    expect(find.byIcon(Icons.hourglass_top), findsNothing);
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
