import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/widgets/cover_art.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: child)));

void main() {
  group('stableHash', () {
    test('is FNV-1a, the same number on every platform (known values of the algorithm)', () {
      expect(stableHash(''), 0x811c9dc5);
      expect(stableHash('a'), 0xe40c292c);
      expect(stableHash('foobar'), 0xbf9cf968);
    });

    test('is the same as the textbook algorithm done with big integers, also for the ids of the fake world', () {
      BigInt reference(String text) {
        var h = BigInt.from(0x811c9dc5);
        final prime = BigInt.from(0x01000193);
        final mask = BigInt.parse('ffffffff', radix: 16);
        for (final unit in text.codeUnits) {
          h = ((h ^ BigInt.from(unit)) * prime) & mask;
        }
        return h;
      }

      final samples = [
        '',
        'a',
        'Sơn Tùng',
        '😀',
        for (var n = 1; n <= 30; n++) 'f4e00000-0000-4000-9000-${n.toString().padLeft(12, '0')}',
        for (var n = 1; n <= 8; n++) 'f4e00000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
        '0c1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b',
      ];
      for (final text in samples) {
        expect(BigInt.from(stableHash(text)), reference(text), reason: '"$text"');
      }
    });

    test('gives different colours to ids that differ only in the last characters, like the ids of the fake world', () {
      // In a browser, a hash that lost its low bits gave all of these the same colour.
      final colours = {for (var n = 1; n <= 8; n++) stableHash('f4e00000-0000-4000-8000-${n.toString().padLeft(12, '0')}') % 8};
      expect(colours.length, 8);
    });

    test('stays within 32 bits and differs for different texts', () {
      final hashes = {for (var i = 0; i < 200; i++) stableHash('track-$i')};
      expect(hashes.length, 200);
      expect(hashes.every((h) => h >= 0 && h <= 0xffffffff), isTrue);
    });
  });

  group('the gradient', () {
    test('is always the same for the same track', () {
      expect(CoverArt.gradientFor('0c1f2a3b-4c5d'), CoverArt.gradientFor('0c1f2a3b-4c5d'));
    });

    test('is one of the pairs of the design system', () {
      for (var i = 0; i < 50; i++) {
        expect(AppGradients.cover, contains(CoverArt.gradientFor('id-$i')));
      }
    });

    test('varies between tracks, so a list does not look like one colour', () {
      final pairs = {for (var i = 0; i < 100; i++) CoverArt.gradientFor('f4e00000-0000-4000-9000-${i.toString().padLeft(12, '0')}')};
      expect(pairs.length, greaterThanOrEqualTo(AppGradients.cover.length - 1));
    });
  });

  group('the widget', () {
    testWidgets('draws the gradient, with a music note, when the track has no image', (tester) async {
      await tester.pumpWidget(_wrap(const CoverArt(trackId: 't1', size: 96)));

      expect(find.byKey(const Key('coverGradient')), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byKey(const Key('coverImage')), findsNothing);
      expect(tester.getSize(find.byType(CoverArt)), const Size(96, 96));
    });

    testWidgets('leaves out the note when it is too small to be seen', (tester) async {
      await tester.pumpWidget(_wrap(const CoverArt(trackId: 't1', size: 32)));
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);
      expect(find.byKey(const Key('coverGradient')), findsOneWidget);
    });

    testWidgets('asks for the image when there is an address', (tester) async {
      await tester.pumpWidget(_wrap(const CoverArt(trackId: 't1', imageUrl: 'http://img.test/c.jpg')));
      expect(find.byKey(const Key('coverImage')), findsOneWidget);
    });

    testWidgets('falls back to the gradient when the image cannot be loaded', (tester) async {
      await tester.pumpWidget(_wrap(const CoverArt(trackId: 't1', imageUrl: 'http://img.test/missing.jpg')));
      // The test environment answers every network request with an error, which the image reports a moment later.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(find.byKey(const Key('coverGradient')), findsOneWidget);
    }, skip: kIsWeb); // the browser's test environment loads images in its own way (the failure is simulated for the VM)

    testWidgets('is decoration: a screen reader skips it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const CoverArt(trackId: 't1')));
      expect(find.byType(CoverArt), findsOneWidget);
      expect(tester.getSemantics(find.byType(CoverArt)).label, isEmpty);
      handle.dispose();
    });
  });
}
