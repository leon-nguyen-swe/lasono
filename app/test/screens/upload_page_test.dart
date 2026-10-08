import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/audio_picker.dart';
import 'package:lasono_app/core/text/file_size.dart';
import 'package:lasono_app/data/fake_flags.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/screens/upload_page.dart';

import '../support/test_harness.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The upload route of the backend, with an answer a test can change, and a record of what was sent.
class _Backend {
  final uploads = <String>[];
  Completer<http.Response>? gate;
  http.Response Function() answer = () => _json({'trackId': 'new-track-1'}, 201);

  late final MockClient client = MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/api/v1/tracks') {
      uploads.add(request.body);
      final pending = gate;
      if (pending != null) return pending.future;
      return answer();
    }
    if (request.method == 'GET' && request.url.path == '/api/v1/tracks/new-track-1') {
      return _json({
        'id': 'new-track-1',
        'title': 'Bài của tôi',
        'description': '',
        'status': 'PROCESSING',
        'ownerId': 'u-1',
        'visibility': 'PUBLIC',
      });
    }
    return _json({'items': [], 'nextCursor': null});
  });
}

PickedAudio _file(String name, {int length = 3000}) => PickedAudio(name: name, bytes: Uint8List(length)..fillRange(0, length, 1));

void main() {
  group('helpers', () {
    test('checkAudioFile accepts mp3 and wav of a sensible size, in any letter case', () {
      expect(checkAudioFile(name: 'a.mp3', length: 10), isNull);
      expect(checkAudioFile(name: 'A.WAV', length: 10), isNull);
    });

    test('checkAudioFile says what is wrong with other files', () {
      expect(checkAudioFile(name: 'a.txt', length: 10), contains('MP3 hoặc WAV'));
      expect(checkAudioFile(name: 'a.mp3', length: 0), 'File này trống.');
      expect(checkAudioFile(name: 'a.mp3', length: maxUploadBytes + 1), contains('50 MB'));
      expect(checkAudioFile(name: 'a.mp3', length: maxUploadBytes), isNull);
    });

    test('titleFromFileName drops the extension and the underscores', () {
      expect(titleFromFileName('my_song.mp3'), 'my song');
      expect(titleFromFileName('Bài hát số 1.final.wav'), 'Bài hát số 1.final');
      expect(titleFromFileName('noextension'), 'noextension');
      expect(titleFromFileName('.mp3'), '.mp3', reason: 'a name that is only an extension stays as it is');
    });

    test('formatFileSize', () {
      expect(formatFileSize(900), '900 B');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(4404019), '4,2 MB');
      expect(formatFileSize(150 * 1024 * 1024), '150 MB');
    });

    test('describeUploadError translates what the server is known to say, and keeps the rest', () {
      String say(String message, [RepositoryErrorKind kind = RepositoryErrorKind.invalid]) =>
          describeUploadError(RepositoryException(message, kind: kind));
      expect(say('Unsupported audio format'), contains('MP3 hoặc WAV'));
      expect(say('File too large (max 50 MB)'), contains('50 MB'));
      expect(say('Upload timed out'), contains('quá lâu'));
      expect(say('Some other detail'), 'Some other detail');
      expect(say('x', RepositoryErrorKind.network), contains('kết nối'));
      expect(describeUploadError(StateError('x')), 'Đã có lỗi xảy ra. Hãy thử lại.');
    });
  });

  group('the upload page', () {
    late _Backend backend;
    late PickedAudio? next;
    var picks = 0;

    setUp(() {
      backend = _Backend();
      next = _file('my_song.mp3');
      picks = 0;
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<TestEnv> open(WidgetTester tester, {bool signedIn = true, double width = 1280}) async {
      TestEnv.window(tester, width: width, height: 1000);
      final env = await TestEnv.create(signedIn: signedIn, client: backend.client, flags: const FakeFlags());
      await tester.pumpWidget(env.app(location: '/upload', pickAudio: () async {
        picks++;
        return next;
      }));
      await settle(tester);
      return env;
    }

    Future<void> pick(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('pickButton')));
      await settle(tester);
    }

    testWidgets('a visitor who is not logged in is sent to the login page and brought back', (tester) async {
      await open(tester, signedIn: false);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
      expect(find.byKey(const Key('dropZone')), findsNothing);
    });

    testWidgets('starts with the drop zone only: no form until there is a file', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('uploadTitle')), findsOneWidget);
      expect(find.byKey(const Key('dropZone')), findsOneWidget);
      expect(find.byKey(const Key('titleField')), findsNothing);
      expect(find.byKey(const Key('uploadSubmit')), findsNothing);
    });

    testWidgets('choosing a file shows its name and size, and fills the title from the name', (tester) async {
      await open(tester);
      await pick(tester);

      expect(find.byKey(const Key('pickedName')), findsOneWidget);
      expect(find.text('my_song.mp3'), findsOneWidget);
      expect(find.text('3 KB'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('titleField'))).controller!.text, 'my song');
    });

    testWidgets('the whole zone can be pressed, not only the button', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('dropZone')));
      await settle(tester);
      expect(picks, 1);
      expect(find.byKey(const Key('titleField')), findsOneWidget);
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      next = null;
      await open(tester);
      await pick(tester);
      expect(find.byKey(const Key('titleField')), findsNothing);
      expect(find.byKey(const Key('fileError')), findsNothing);
    });

    testWidgets('a file that is not mp3 or wav is refused with a reason, and no form is shown', (tester) async {
      next = _file('notes.txt');
      await open(tester);
      await pick(tester);

      expect(find.byKey(const Key('fileError')), findsOneWidget);
      expect(find.textContaining('MP3 hoặc WAV'), findsWidgets);
      expect(find.byKey(const Key('titleField')), findsNothing);
    });

    testWidgets('a wrong file chosen after a good one does not replace it', (tester) async {
      await open(tester);
      await pick(tester);
      next = _file('notes.txt');
      await tester.tap(find.byKey(const Key('changeFileButton')));
      await settle(tester);

      expect(find.byKey(const Key('fileError')), findsOneWidget);
      expect(find.text('my_song.mp3'), findsOneWidget);
    });

    testWidgets('changing the file keeps the title the user typed', (tester) async {
      await open(tester);
      await pick(tester);
      await tester.enterText(find.byKey(const Key('titleField')), 'Tên của tôi');
      next = _file('other.wav');
      await tester.tap(find.byKey(const Key('changeFileButton')));
      await settle(tester);

      expect(find.text('other.wav'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('titleField'))).controller!.text, 'Tên của tôi');
    });

    testWidgets('sends the title, the description and the file, public by default, and leaves the page after', (tester) async {
      await open(tester);
      await pick(tester);
      await tester.enterText(find.byKey(const Key('titleField')), 'Bài của tôi');
      await tester.enterText(find.byKey(const Key('descriptionField')), 'Mô tả ngắn');
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await settle(tester);

      expect(backend.uploads.length, 1);
      final sent = backend.uploads.single;
      expect(sent, contains('Bài của tôi'));
      expect(sent, contains('Mô tả ngắn'));
      expect(sent, contains('PUBLIC'));
      expect(sent, contains('my_song.mp3'));
      expect(find.byKey(const Key('uploadTitle')), findsNothing, reason: 'the user is taken to the new track');
      expect(find.byKey(const Key('trackProcessing')), findsOneWidget, reason: 'which the server is still processing');
      expect(find.text('Bài của tôi'), findsWidgets);
    });

    testWidgets('the private switch sends PRIVATE', (tester) async {
      await open(tester);
      await pick(tester);
      await tester.tap(find.byKey(const Key('privateSwitch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await settle(tester);

      expect(backend.uploads.single, contains('PRIVATE'));
    });

    testWidgets('an empty title is said under the field and nothing is sent', (tester) async {
      await open(tester);
      await pick(tester);
      await tester.enterText(find.byKey(const Key('titleField')), '   ');
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await tester.pump();

      expect(find.text('Hãy nhập tiêu đề.'), findsOneWidget);
      expect(backend.uploads, isEmpty);
    });

    testWidgets('while it uploads, a progress bar shows, the form is locked, and a second press sends nothing', (tester) async {
      backend.gate = Completer<http.Response>();
      await open(tester);
      await pick(tester);
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('uploadProgress')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('titleField'))).enabled, isFalse);
      expect(tester.widget<FilledButton>(find.byKey(const Key('uploadSubmit'))).onPressed, isNull);

      backend.gate!.complete(_json({'trackId': 'new-track-1'}, 201));
      await settle(tester);
      expect(backend.uploads.length, 1);
    });

    testWidgets('a refusal of the server is explained in Vietnamese, the page stays, and a second try works', (tester) async {
      backend.answer = () => http.Response('', 415);
      await open(tester);
      await pick(tester);
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await settle(tester);

      expect(find.byKey(const Key('uploadError')), findsOneWidget);
      expect(find.textContaining('MP3 hoặc WAV'), findsWidgets);
      expect(find.byKey(const Key('uploadProgress')), findsNothing);

      backend.answer = () => _json({'trackId': 'new-track-1'}, 201);
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await settle(tester);
      expect(backend.uploads.length, 2);
      expect(find.byKey(const Key('uploadTitle')), findsNothing);
    });

    testWidgets('a server that is down is reported as a problem of the server', (tester) async {
      backend.answer = () => http.Response('', 500);
      await open(tester);
      await pick(tester);
      await tester.tap(find.byKey(const Key('uploadSubmit')));
      await settle(tester);

      expect(find.textContaining('Máy chủ đang gặp sự cố'), findsOneWidget);
    });

    testWidgets('fits a phone without overflow', (tester) async {
      await open(tester, width: 390);
      await pick(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
