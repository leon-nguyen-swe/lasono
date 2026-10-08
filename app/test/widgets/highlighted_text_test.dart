import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/widgets/highlighted_text.dart';

import '../support/test_harness.dart';

void main() {
  testWidgets('without a query it is a plain text that find.text can find', (tester) async {
    await tester.pumpWidget(themed(const HighlightedText('Sơn Tùng')));
    expect(find.text('Sơn Tùng'), findsOneWidget);
  });

  testWidgets('a query that matches nothing is also a plain text', (tester) async {
    await tester.pumpWidget(themed(const HighlightedText('Sơn Tùng', query: 'xyz')));
    expect(find.text('Sơn Tùng'), findsOneWidget);
  });

  testWidgets('the part that matches is in the accent colour and bold, the rest is not', (tester) async {
    await tester.pumpWidget(themed(const HighlightedText('Sơn Tùng', query: 'son')));

    final text = tester.widget<Text>(find.byType(Text).first);
    final accent = AppColors.dark.accent;
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text), ['Sơn', ' Tùng']);
    expect(spans[0].style?.color, accent);
    expect(spans[0].style?.fontWeight, FontWeight.w700);
    expect(spans[1].style, isNull);
    expect(text.textSpan!.toPlainText(), 'Sơn Tùng');
  });

  testWidgets('keeps the line limit and the ellipsis it was given', (tester) async {
    await tester.pumpWidget(themed(const HighlightedText('Sơn Tùng', query: 'son', maxLines: 1, overflow: TextOverflow.ellipsis)));
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
