import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/widgets/cover_art.dart';
import 'package:lasono_app/widgets/user_widgets.dart';

import '../support/test_harness.dart';

const _profile = Profile(userId: 'u-1', displayName: 'Sơn Tùng', followerCount: 1280, followingCount: 12);

void main() {
  group('UserTile', () {
    testWidgets('shows the name and how many follow, in short form', (tester) async {
      await tester.pumpWidget(themed(const UserTile(profile: _profile)));
      expect(find.text('Sơn Tùng'), findsOneWidget);
      expect(find.text('1,3K người theo dõi'), findsOneWidget);
      expect(find.text('ST'), findsOneWidget, reason: 'the initials of the avatar');
    });

    testWidgets('can be pressed, and has something at the end', (tester) async {
      var opened = 0;
      await tester.pumpWidget(themed(UserTile(profile: _profile, onTap: () => opened++, trailing: const Text('nút'))));

      await tester.tap(find.text('Sơn Tùng'));

      expect(opened, 1);
      expect(find.text('nút'), findsOneWidget);
    });

    testWidgets('a long name is cut and nothing overflows', (tester) async {
      TestEnv.window(tester, width: 320);
      await tester.pumpWidget(themed(UserTile(
        profile: const Profile(userId: 'u', displayName: 'Một cái tên người dùng dài đến mức không vừa một dòng của màn hình nhỏ'),
        trailing: const Text('Theo dõi'),
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('StatBlock', () {
    testWidgets('shows the number in short form with its name under it', (tester) async {
      await tester.pumpWidget(themed(const StatBlock(value: 12345, label: 'Người theo dõi')));
      expect(find.byKey(const Key('statValue')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('statValue'))).data, '12K');
      expect(find.text('Người theo dõi'), findsOneWidget);
    });

    testWidgets('can be pressed', (tester) async {
      var opened = 0;
      await tester.pumpWidget(themed(StatBlock(value: 3, label: 'Bài hát', onTap: () => opened++)));
      await tester.tap(find.text('Bài hát'));
      expect(opened, 1);
    });
  });

  group('ProfileHeader', () {
    Widget header({int? tracks = 14, VoidCallback? onFollowers, VoidCallback? onFollowing}) => themed(
          SingleChildScrollView(
            child: ProfileHeader(
              profile: _profile,
              trackCount: tracks,
              action: const Text('hành động'),
              onFollowers: onFollowers,
              onFollowing: onFollowing,
            ),
          ),
        );

    testWidgets('shows the name, the three numbers, the avatar and the action', (tester) async {
      TestEnv.window(tester, width: 1100);
      await tester.pumpWidget(header());

      expect(tester.widget<Text>(find.byKey(const Key('profileName'))).data, 'Sơn Tùng');
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('statFollowers')), matching: find.byKey(const Key('statValue')))).data, '1,3K');
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('statFollowing')), matching: find.byKey(const Key('statValue')))).data, '12');
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('statTracks')), matching: find.byKey(const Key('statValue')))).data, '14');
      expect(find.byKey(const Key('profileAvatar')), findsOneWidget);
      expect(find.text('hành động'), findsOneWidget);
    });

    testWidgets('leaves out the number of tracks while it is not known', (tester) async {
      TestEnv.window(tester, width: 1100);
      await tester.pumpWidget(header(tracks: null));
      expect(find.byKey(const Key('statTracks')), findsNothing);
    });

    testWidgets('the banner has the colours of the user, the same as their cover colours would be', (tester) async {
      TestEnv.window(tester, width: 1100);
      await tester.pumpWidget(header());
      final decoration = tester.widget<Container>(find.byKey(const Key('profileBanner'))).decoration! as BoxDecoration;
      final (from, to) = CoverArt.gradientFor('u-1');
      expect((decoration.gradient! as LinearGradient).colors, [from, to]);
    });

    testWidgets('the avatar is half over the edge of the banner', (tester) async {
      TestEnv.window(tester, width: 1100);
      await tester.pumpWidget(header());
      final banner = tester.getRect(find.byKey(const Key('profileBanner')));
      final avatar = tester.getRect(find.byKey(const Key('profileAvatar')));
      expect(avatar.center.dy, closeTo(banner.bottom, 1));
    });

    testWidgets('the banner is lower on a phone', (tester) async {
      TestEnv.window(tester, width: 1100);
      await tester.pumpWidget(header());
      final wide = tester.getSize(find.byKey(const Key('profileBanner'))).height;

      TestEnv.window(tester, width: 390);
      await tester.pumpWidget(header());
      expect(tester.getSize(find.byKey(const Key('profileBanner'))).height, lessThan(wide));
    });

    testWidgets('the numbers open the lists', (tester) async {
      TestEnv.window(tester, width: 1100);
      final opened = <String>[];
      await tester.pumpWidget(header(onFollowers: () => opened.add('followers'), onFollowing: () => opened.add('following')));

      await tester.tap(find.byKey(const Key('statFollowers')));
      await tester.tap(find.byKey(const Key('statFollowing')));

      expect(opened, ['followers', 'following']);
    });

    testWidgets('fits a very narrow phone', (tester) async {
      TestEnv.window(tester, width: 320);
      await tester.pumpWidget(header());
      expect(tester.takeException(), isNull);
      expect(find.text('hành động'), findsOneWidget);
    });
  });
}
