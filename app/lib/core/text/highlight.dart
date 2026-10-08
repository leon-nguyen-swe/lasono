import 'fold_accents.dart';

/// A part of a text, and whether it is a part the search found.
class TextPiece {
  const TextPiece(this.text, {required this.match});

  final String text;
  final bool match;

  @override
  bool operator ==(Object other) => other is TextPiece && other.text == text && other.match == match;

  @override
  int get hashCode => Object.hash(text, match);

  @override
  String toString() => '${match ? '[' : ''}$text${match ? ']' : ''}';
}

/// Cuts [text] into the parts that match [query] and the parts that do not, ignoring case and accents like the search does:
/// searching `son` marks the `Sơn` of `Sơn Tùng`. The text keeps its own letters; only the matching is folded.
///
/// An empty query, or one that finds nothing, gives the whole text as one part that does not match.
List<TextPiece> highlightPieces(String text, String query) {
  final wanted = foldAccents(query.trim());
  if (text.isEmpty || wanted.isEmpty) return [TextPiece(text, match: false)];

  // The folded text, and for each character of it the position in [text] it came from. A letter that is written as a
  // base plus a separate mark folds to one character, so the positions of the original are not the positions of the folded.
  final runes = text.runes.toList();
  final folded = StringBuffer();
  final origin = <int>[]; // folded UTF-16 index -> index of the rune in [runes]
  for (final (index, rune) in runes.indexed) {
    final piece = foldAccents(String.fromCharCode(rune));
    for (var i = 0; i < piece.length; i++) {
      origin.add(index);
    }
    folded.write(piece);
  }
  final haystack = folded.toString();

  final pieces = <TextPiece>[];
  var runeCursor = 0; // the next rune of [runes] not yet put in a piece
  var searchFrom = 0;
  String slice(int from, int to) => String.fromCharCodes(runes.sublist(from, to));
  while (true) {
    final found = haystack.indexOf(wanted, searchFrom);
    if (found == -1) break;
    final firstRune = origin[found];
    var endRune = origin[found + wanted.length - 1] + 1;
    // Marks that stand after the last letter belong to it.
    while (endRune < runes.length && foldAccents(String.fromCharCode(runes[endRune])).isEmpty) {
      endRune++;
    }
    if (firstRune > runeCursor) pieces.add(TextPiece(slice(runeCursor, firstRune), match: false));
    pieces.add(TextPiece(slice(firstRune, endRune), match: true));
    runeCursor = endRune;
    searchFrom = found + wanted.length;
  }
  if (pieces.isEmpty) return [TextPiece(text, match: false)];
  if (runeCursor < runes.length) pieces.add(TextPiece(slice(runeCursor, runes.length), match: false));
  return pieces;
}
