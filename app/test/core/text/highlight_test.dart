import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/text/highlight.dart';

TextPiece _hit(String text) => TextPiece(text, match: true);
TextPiece _rest(String text) => TextPiece(text, match: false);

void main() {
  group('highlightPieces', () {
    test('marks the part that matches, in the letters of the text', () {
      expect(highlightPieces('Sơn Tùng M-TP', 'son'), [_hit('Sơn'), _rest(' Tùng M-TP')]);
    });

    test('ignores case and accents on both sides', () {
      expect(highlightPieces('Đen Vâu', 'ĐEN'), [_hit('Đen'), _rest(' Vâu')]);
      expect(highlightPieces('Đen Vâu', 'vau'), [_rest('Đen '), _hit('Vâu')]);
      expect(highlightPieces('Tháng Tư là lời nói dối', 'thang tu'), [_hit('Tháng Tư'), _rest(' là lời nói dối')]);
    });

    test('marks every place it matches', () {
      expect(highlightPieces('la la land', 'la'), [_hit('la'), _rest(' '), _hit('la'), _rest(' '), _hit('la'), _rest('nd')]);
    });

    test('a query with spaces around it is trimmed', () {
      expect(highlightPieces('Lạc trôi', '  lac '), [_hit('Lạc'), _rest(' trôi')]);
    });

    test('a text with the marks written apart from the letters is matched too, and the marks stay with their letter', () {
      const decomposed = 'Sơn Tùng'; // Sơn Tùng with separate marks
      expect(highlightPieces(decomposed, 'son'), [_hit('Sơn'), _rest(' Tùng')]);
      expect(highlightPieces(decomposed, 'tung'), [_rest('Sơn '), _hit('Tùng')]);
    });

    test('nothing to find gives the text whole, as not matching', () {
      expect(highlightPieces('Lạc trôi', 'xyz'), [_rest('Lạc trôi')]);
      expect(highlightPieces('Lạc trôi', ''), [_rest('Lạc trôi')]);
      expect(highlightPieces('Lạc trôi', '   '), [_rest('Lạc trôi')]);
      expect(highlightPieces('', 'a'), [_rest('')]);
    });

    test('the pieces put together are always the text', () {
      for (final (text, query) in [('Hãy trao cho anh', 'ao'), ('Em của ngày hôm qua', 'em'), ('Neon Rain 🎵 night', 'rain'), ('aaa', 'aa')]) {
        expect(highlightPieces(text, query).map((p) => p.text).join(), text, reason: '$text / $query');
      }
    });

    test('a match at the very end has no empty piece after it', () {
      expect(highlightPieces('Nắng ấm xa dần', 'dan'), [_rest('Nắng ấm xa '), _hit('dần')]);
    });

    test('text with characters outside the basic plane is cut at whole characters', () {
      expect(highlightPieces('🎵 Rain', 'rain'), [_rest('🎵 '), _hit('Rain')]);
    });
  });
}
