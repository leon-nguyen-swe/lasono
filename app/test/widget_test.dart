import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/main.dart';

void main() {
  testWidgets('shows the LaSono title screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.text('LaSono'), findsOneWidget);
  });

  testWidgets('does not ship the counter demo', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
