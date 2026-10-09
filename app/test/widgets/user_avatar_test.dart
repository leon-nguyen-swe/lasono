import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/widgets/user_avatar.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: child)));

void main() {
  group('initialsOf', () {
    const cases = {
      'Sơn Tùng': 'ST',
      'Đen Vâu': 'ĐV',
      'Hà Anh Tuấn': 'HT',
      'Minh Anh': 'MA',
      'DJ Kaito': 'DK',
      'alice': 'A',
      'ánh': 'Á',
      '  Maya   Chen  ': 'MC',
      '': '?',
      '   ': '?',
    };
    cases.forEach((name, expected) {
      test('"$name" gives $expected', () => expect(UserAvatar.initialsOf(name), expected));
    });

    test('an emoji is one letter, not half of one', () {
      expect(UserAvatar.initialsOf('😀 Nam'), '😀N');
    });
  });

  group('the colour', () {
    test('is the same for the same user and comes from the palette', () {
      expect(UserAvatar.colorFor('u1'), UserAvatar.colorFor('u1'));
      expect(UserAvatar.palette, contains(UserAvatar.colorFor('anything')));
    });

    test('varies between users', () {
      final colours = {for (var i = 0; i < 100; i++) UserAvatar.colorFor('user-$i')};
      expect(colours.length, greaterThanOrEqualTo(UserAvatar.palette.length - 1));
    });

    test('every colour is dark enough for white letters (WCAG 4.5:1)', () {
      for (final colour in UserAvatar.palette) {
        expect(contrastRatio(Colors.white, colour), greaterThanOrEqualTo(4.5), reason: '$colour');
      }
    });
  });

  group('the widget', () {
    testWidgets('shows the initials on the colour of the user, in a circle of the asked size', (tester) async {
      await tester.pumpWidget(_wrap(const UserAvatar(userId: 'u1', displayName: 'Sơn Tùng', size: 56)));

      expect(find.text('ST'), findsOneWidget);
      expect(tester.getSize(find.byType(UserAvatar)), const Size(56, 56));
      final colour = tester.widget<Container>(find.byKey(const Key('avatarInitials'))).color;
      expect(colour, UserAvatar.colorFor('u1'));
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('is announced by the name of the user', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const UserAvatar(userId: 'u1', displayName: 'Sơn Tùng')));
      expect(tester.getSemantics(find.byType(UserAvatar)).label, 'Sơn Tùng');
      handle.dispose();
    });

    testWidgets('asks for the image when there is an address, and falls back to the initials when it fails', (tester) async {
      await tester.pumpWidget(
        _wrap(const UserAvatar(userId: 'u1', displayName: 'Đen Vâu', imageUrl: 'http://img.test/a.jpg')),
      );
      expect(find.byKey(const Key('avatarImage')), findsOneWidget);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(find.text('ĐV'), findsOneWidget);
    }, skip: kIsWeb); // the browser's test environment loads images in its own way (the failure is simulated for the VM)
  });
}
