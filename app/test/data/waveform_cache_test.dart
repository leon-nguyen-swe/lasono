import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/data/track_repository.dart';
import 'package:lasono_app/data/waveform_cache.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/models/track_page.dart';

class _Tracks implements TrackRepository {
  final asked = <String>[];
  Completer<void>? gate;
  Object? failure;
  List<double>? answer = const [0.1, 0.9, 0.5];

  @override
  Future<Track> getTrack(String id) async {
    asked.add(id);
    await gate?.future;
    if (failure != null) throw failure!;
    return Track(id: id, title: 'T', description: '', status: 'READY', waveform: answer);
  }

  @override
  Future<TrackPage> listTracks({String? cursor, int? limit}) => throw UnimplementedError();
  @override
  Future<TrackPage> listUserTracks(String userId, {String? cursor, int? limit}) => throw UnimplementedError();
  @override
  Future<Uri> fetchStreamUrl(String id) => throw UnimplementedError();
  @override
  Future<Track> updateTrack(String id, {String? title, String? description, String? visibility}) => throw UnimplementedError();
  @override
  Future<void> deleteTrack(String id) => throw UnimplementedError();
  @override
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) =>
      throw UnimplementedError();
}

Track _track(String id, {String status = 'READY', List<double>? waveform}) =>
    Track(id: id, title: 'T', description: '', status: status, waveform: waveform);

void main() {
  test('reads the waveform of a track that has none, once', () async {
    final tracks = _Tracks();
    final cache = WaveformCache(tracks);

    expect(await cache.peaksOf(_track('a')), [0.1, 0.9, 0.5]);
    expect(await cache.peaksOf(_track('a')), [0.1, 0.9, 0.5]);

    expect(tracks.asked, ['a']);
    expect(cache.cached(_track('a')), isNotNull);
  });

  test('uses the waveform the track already has, without asking', () async {
    final tracks = _Tracks();
    final cache = WaveformCache(tracks);
    final peaks = await cache.peaksOf(_track('a', waveform: const [0.3, 0.4]));
    expect(peaks, [0.3, 0.4]);
    expect(tracks.asked, isEmpty);
  });

  test('two asks at the same moment make one request', () async {
    final tracks = _Tracks()..gate = Completer<void>();
    final cache = WaveformCache(tracks);

    final first = cache.peaksOf(_track('a'));
    final second = cache.peaksOf(_track('a'));
    tracks.gate!.complete();

    expect(await first, [0.1, 0.9, 0.5]);
    expect(await second, [0.1, 0.9, 0.5]);
    expect(tracks.asked, ['a']);
  });

  test('a track that is not ready has no waveform, and nothing is asked', () async {
    final tracks = _Tracks();
    final cache = WaveformCache(tracks);
    expect(await cache.peaksOf(_track('a', status: 'PROCESSING')), isNull);
    expect(await cache.peaksOf(_track('b', status: 'FAILED')), isNull);
    expect(tracks.asked, isEmpty);
  });

  test('a failure gives null, is not remembered, and the next ask tries again', () async {
    final tracks = _Tracks()..failure = const RepositoryException('down', kind: RepositoryErrorKind.network);
    final cache = WaveformCache(tracks);

    expect(await cache.peaksOf(_track('a')), isNull);
    expect(cache.cached(_track('a')), isNull);

    tracks.failure = null;
    expect(await cache.peaksOf(_track('a')), [0.1, 0.9, 0.5]);
    expect(tracks.asked, ['a', 'a']);
  });

  test('a track the server has no waveform for is not kept as an answer', () async {
    final tracks = _Tracks()..answer = null;
    final cache = WaveformCache(tracks);
    expect(await cache.peaksOf(_track('a')), isNull);
    expect(cache.cached(_track('a')), isNull);
  });

  test('clear forgets what was read', () async {
    final tracks = _Tracks();
    final cache = WaveformCache(tracks);
    await cache.peaksOf(_track('a'));
    cache.clear();
    expect(cache.cached(_track('a')), isNull);
    await cache.peaksOf(_track('a'));
    expect(tracks.asked.length, 2);
  });
}
