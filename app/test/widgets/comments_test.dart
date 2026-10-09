import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/comment.dart';
import 'package:lasono_app/widgets/comments.dart';

import '../support/test_harness.dart';

final _now = DateTime.utc(2026, 10, 8, 12);

class _Composer {
  _Composer({this.signedIn = true, this.durationMs = 60000, this.live});

  final bool signedIn;
  final int? durationMs;
  final ValueNotifier<Duration>? live;
  final sent = <(int, String)>[];
  int loginRequests = 0;
  Completer<void>? gate;
  Object? failure;

  Widget widget() => themed(
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CommentComposer(
            viewerId: signedIn ? 'viewer-1' : null,
            viewerName: signedIn ? 'Ann' : null,
            durationMs: durationMs,
            livePosition: live,
            onSubmit: (position, text) async {
              await gate?.future;
              if (failure != null) throw failure!;
              sent.add((position, text));
            },
            onNeedLogin: () => loginRequests++,
          ),
        ),
      );
}

String _chip(WidgetTester tester) {
  final chip = tester.widget<ActionChip>(find.byKey(const Key('momentChip')));
  return (chip.label as Text).data!;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('commentField')), text);
  await tester.pump();
}

void main() {
  group('the composer, signed out', () {
    testWidgets('says to log in, and a press anywhere on the box asks for the login', (tester) async {
      final composer = _Composer(signedIn: false);
      await tester.pumpWidget(composer.widget());

      expect(find.text('Đăng nhập để bình luận'), findsOneWidget);
      expect(find.byKey(const Key('momentChip')), findsNothing);

      await tester.tap(find.byKey(const Key('commentField')));
      expect(composer.loginRequests, 1);
      expect(composer.sent, isEmpty);
    });
  });

  group('the composer, signed in', () {
    testWidgets('the moment is 0:00 when the track is not the one playing', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      expect(_chip(tester), 'Bình luận tại 0:00');
    });

    testWidgets('follows the playing while the user has not started to write', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 83));
      await tester.pumpWidget(_Composer(live: live, durationMs: 300000).widget());
      expect(_chip(tester), 'Bình luận tại 1:23');

      live.value = const Duration(seconds: 90);
      await tester.pump();
      expect(_chip(tester), 'Bình luận tại 1:30');
    });

    testWidgets('keeps the moment where the track was when the user began to write, not where it is when they send', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 12));
      final composer = _Composer(live: live);
      await tester.pumpWidget(composer.widget());

      await _type(tester, 'Hay quá');
      live.value = const Duration(seconds: 40);
      await tester.pump();
      expect(_chip(tester), 'Bình luận tại 0:12');

      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();

      expect(composer.sent, [(12000, 'Hay quá')]);
    });

    testWidgets('emptying the box lets the moment follow the playing again', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 12));
      await tester.pumpWidget(_Composer(live: live).widget());
      await _type(tester, 'a');
      live.value = const Duration(seconds: 30);
      await _type(tester, '');
      expect(_chip(tester), 'Bình luận tại 0:30');
    });

    testWidgets('the moment never goes past the end of the track', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 500));
      final composer = _Composer(live: live, durationMs: 60000);
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'cuối bài');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();
      expect(composer.sent.single.$1, 60000);
    });

    testWidgets('cannot send an empty comment, or one of spaces', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      IconButton send() => tester.widget<IconButton>(find.byKey(const Key('sendComment')));
      expect(send().onPressed, isNull);

      await _type(tester, '    ');
      expect(send().onPressed, isNull);

      await _type(tester, ' a ');
      expect(send().onPressed, isNotNull);
    });

    testWidgets('500 characters are enough and 501 are too many, counting what a person sees (an emoji is one)', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      IconButton send() => tester.widget<IconButton>(find.byKey(const Key('sendComment')));

      await _type(tester, '😀' * 500);
      expect(send().onPressed, isNotNull);
      expect(find.text('Tối đa 500 ký tự'), findsNothing);

      await _type(tester, '😀' * 501);
      expect(send().onPressed, isNull);
      expect(find.text('Tối đa 500 ký tự'), findsOneWidget);
    });

    testWidgets('shows a counter only when the end is near', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      await _type(tester, 'a' * 100);
      expect(find.byKey(const Key('commentCounter')), findsNothing);
      await _type(tester, 'a' * 450);
      expect(find.text('450/500'), findsOneWidget);
    });

    testWidgets('Enter sends it', (tester) async {
      final composer = _Composer();
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'Gửi bằng Enter');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(composer.sent.single.$2, 'Gửi bằng Enter');
    });

    testWidgets('after it is sent the box is empty and ready for the next', (tester) async {
      final composer = _Composer();
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'một');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();

      expect(tester.widget<TextField>(find.byKey(const Key('commentField'))).controller!.text, isEmpty);
      await _type(tester, 'hai');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();
      expect(composer.sent.map((s) => s.$2), ['một', 'hai']);
    });

    testWidgets('while it is being sent a second press sends nothing more', (tester) async {
      final composer = _Composer()..gate = Completer<void>();
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'chậm');

      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('sendComment')), warnIfMissed: false);
      composer.gate!.complete();
      await tester.pump();

      expect(composer.sent.length, 1);
    });

    testWidgets('a failure keeps the text and says why', (tester) async {
      final composer = _Composer()..failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'đừng mất');

      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.widget<TextField>(find.byKey(const Key('commentField'))).controller!.text, 'đừng mất');
      expect(find.textContaining('kết nối'), findsOneWidget);
    });

    testWidgets('a reason the server gives (a position outside the track) is shown as it is', (tester) async {
      final composer = _Composer()
        ..failure = const RepositoryException('positionMs must be between 0 and 213400', kind: RepositoryErrorKind.invalid);
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'x');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('positionMs must be between 0 and 213400'), findsOneWidget);
    });

    testWidgets('when the login ran out it asks to log in again, and keeps the text', (tester) async {
      final composer = _Composer()..failure = const RepositoryException('x', kind: RepositoryErrorKind.unauthorized);
      await tester.pumpWidget(composer.widget());
      await _type(tester, 'giữ lại');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(composer.loginRequests, 1);
      expect(tester.widget<TextField>(find.byKey(const Key('commentField'))).controller!.text, 'giữ lại');
    });
  });

  group('choosing the moment by hand', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('momentChip')));
      await tester.pumpAndSettle();
    }

    testWidgets('pressing the chip opens a box with the current moment, and a valid time replaces it', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 12));
      final composer = _Composer(live: live);
      await tester.pumpWidget(composer.widget());

      await openDialog(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('momentField'))).controller!.text, '0:12');
      await tester.enterText(find.byKey(const Key('momentField')), '0:45');
      await tester.tap(find.byKey(const Key('momentOk')));
      await tester.pumpAndSettle();

      expect(_chip(tester), 'Bình luận tại 0:45');
      live.value = const Duration(seconds: 50);
      await tester.pump();
      expect(_chip(tester), 'Bình luận tại 0:45', reason: 'a moment set by hand does not follow the playing');

      await _type(tester, 'ở giây 45');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pump();
      expect(composer.sent.single.$1, 45000);
    });

    testWidgets('something that is not a time is refused with an example', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('momentField')), 'abc');
      await tester.tap(find.byKey(const Key('momentOk')));
      await tester.pump();

      expect(find.textContaining('m:ss'), findsWidgets);
      expect(find.byKey(const Key('momentField')), findsOneWidget, reason: 'the box stays open');
    });

    testWidgets('a time past the end of the track is refused and says how long the track is', (tester) async {
      await tester.pumpWidget(_Composer(durationMs: 60000).widget());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('momentField')), '2:00');
      await tester.tap(find.byKey(const Key('momentOk')));
      await tester.pump();

      expect(find.text('Tối đa 1:00'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await tester.pumpWidget(_Composer().widget());
      await openDialog(tester);
      await tester.enterText(find.byKey(const Key('momentField')), '0:30');
      await tester.tap(find.byKey(const Key('momentCancel')));
      await tester.pumpAndSettle();
      expect(_chip(tester), 'Bình luận tại 0:00');
    });

    testWidgets('a button then offers to go back to the position of the playing', (tester) async {
      final live = ValueNotifier(const Duration(seconds: 20));
      await tester.pumpWidget(_Composer(live: live).widget());
      expect(find.byKey(const Key('useLivePosition')), findsNothing);

      await openDialog(tester);
      await tester.enterText(find.byKey(const Key('momentField')), '0:05');
      await tester.tap(find.byKey(const Key('momentOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('useLivePosition')), findsOneWidget);

      await tester.tap(find.byKey(const Key('useLivePosition')));
      await tester.pump();

      expect(_chip(tester), 'Bình luận tại 0:20');
      expect(find.byKey(const Key('useLivePosition')), findsNothing);
    });
  });

  group('the list', () {
    late TestEnv env;

    setUp(() async {
      env = await TestEnv.create();
    });

    Comment comment(String id, String author, int ms, String text, {DateTime? at}) =>
        Comment(id: id, trackId: 't', authorId: author, positionMs: ms, text: text, createdAt: at ?? _now.subtract(const Duration(hours: 3)));

    Widget list(List<Comment> comments, {String? viewer, String owner = 'owner', ValueChanged<int>? onSeekTo, Future<void> Function(Comment)? onDelete}) {
      return themed(
        SingleChildScrollView(
          child: CommentList(
            comments: comments,
            directory: env.repositories.directory,
            viewerId: viewer,
            trackOwnerId: owner,
            onSeekTo: onSeekTo ?? (_) {},
            onDelete: onDelete ?? (_) async {},
            clock: () => _now,
          ),
        ),
      );
    }

    final sonTung = FakeWorld.userId(1);
    final denVau = FakeWorld.userId(2);

    testWidgets('shows the text, the name of the author, the moment and how long ago', (tester) async {
      await tester.pumpWidget(list([comment('c1', sonTung, 83000, 'Đoạn này hay quá!')]));
      await tester.pump();
      await tester.pump();

      expect(find.text('Đoạn này hay quá!'), findsOneWidget);
      expect(find.text('Sơn Tùng'), findsOneWidget);
      expect(find.text('tại 1:23'), findsOneWidget);
      expect(find.text('3 giờ trước'), findsOneWidget);
    });

    testWidgets('asks for the names of all the authors in one request', (tester) async {
      await tester.pumpWidget(list([
        comment('c1', sonTung, 1000, 'một'),
        comment('c2', denVau, 2000, 'hai'),
        comment('c3', sonTung, 3000, 'ba'),
      ]));
      await tester.pump();
      await tester.pump();

      expect(env.repositories.directory.cached(sonTung), isNotNull);
      expect(env.repositories.directory.cached(denVau), isNotNull);
      expect(find.text('Sơn Tùng'), findsNWidgets(2));
    });

    testWidgets('shows three dots in the place of a name that has not arrived yet', (tester) async {
      await tester.pumpWidget(list([comment('c1', sonTung, 1000, 'chờ')]));
      expect(find.text('…'), findsWidgets, reason: 'the name, and the initials of the avatar made from it');
      await tester.pump();
      await tester.pump();
      expect(find.text('…'), findsNothing);
      expect(find.text('Sơn Tùng'), findsOneWidget);
    });

    testWidgets('pressing the moment jumps to it', (tester) async {
      final seeks = <int>[];
      await tester.pumpWidget(list([comment('c1', sonTung, 83000, 'x')], onSeekTo: seeks.add));
      await tester.tap(find.byKey(const Key('commentTime')));
      expect(seeks, [83000]);
    });

    testWidgets('the author can delete their comment, the owner of the track can delete any, a stranger and a visitor cannot', (tester) async {
      final mine = comment('c1', 'viewer-1', 1000, 'của tôi');
      final theirs = comment('c2', sonTung, 2000, 'của người khác');

      await tester.pumpWidget(list([mine, theirs], viewer: 'viewer-1'));
      expect(find.descendant(of: find.byKey(const Key('comment-c1')), matching: find.byKey(const Key('deleteComment'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('comment-c2')), matching: find.byKey(const Key('deleteComment'))), findsNothing);

      await tester.pumpWidget(list([mine, theirs], viewer: 'the-owner', owner: 'the-owner'));
      expect(find.byKey(const Key('deleteComment')), findsNWidgets(2));

      await tester.pumpWidget(list([mine, theirs], viewer: null));
      expect(find.byKey(const Key('deleteComment')), findsNothing);
    });

    testWidgets('deleting asks first: cancel does nothing, confirm deletes', (tester) async {
      final deleted = <String>[];
      final mine = comment('c1', 'viewer-1', 1000, 'của tôi');
      await tester.pumpWidget(list([mine], viewer: 'viewer-1', onDelete: (c) async => deleted.add(c.id)));

      await tester.tap(find.byKey(const Key('deleteComment')));
      await tester.pumpAndSettle();
      expect(find.text('Xoá bình luận?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelButton')));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);

      await tester.tap(find.byKey(const Key('deleteComment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmButton')));
      await tester.pumpAndSettle();
      expect(deleted, ['c1']);
    });

    testWidgets('a delete that fails says why', (tester) async {
      final mine = comment('c1', 'viewer-1', 1000, 'của tôi');
      await tester.pumpWidget(list(
        [mine],
        viewer: 'viewer-1',
        onDelete: (_) async => throw const RepositoryException('x', kind: RepositoryErrorKind.forbidden),
      ));

      await tester.tap(find.byKey(const Key('deleteComment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmButton')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('quyền'), findsOneWidget);
    });

    testWidgets('a comment without a date has no "ago"', (tester) async {
      const undated = Comment(id: 'c1', trackId: 't', authorId: 'u', positionMs: 1000, text: 'không có ngày');
      await tester.pumpWidget(list([undated]));
      expect(find.textContaining('trước'), findsNothing);
      expect(find.text('không có ngày'), findsOneWidget);
    });
  });
}
