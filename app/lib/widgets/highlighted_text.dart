import 'package:flutter/material.dart';

import '../core/text/highlight.dart';
import '../core/theme/theme.dart';

/// A text in which the parts that match a search are shown in the accent colour and bold. Without a query it is a plain
/// [Text], so everything that looks for the text still finds it.
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.text, {super.key, this.query, this.style, this.maxLines, this.overflow});

  final String text;

  /// What was searched for; null or empty for no highlight.
  final String? query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final q = query;
    if (q == null || q.trim().isEmpty) return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    final pieces = highlightPieces(text, q);
    if (!pieces.any((p) => p.match)) return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    final c = AppColors.of(context);
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final piece in pieces)
            TextSpan(
              text: piece.text,
              style: piece.match ? TextStyle(color: c.accent, fontWeight: FontWeight.w700) : null,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
