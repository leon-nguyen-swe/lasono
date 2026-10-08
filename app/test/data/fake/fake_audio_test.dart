import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_audio.dart';

void main() {
  test('is a well formed 8 kHz mono 8-bit WAV of the asked length', () {
    final wav = FakeAudio.wav(3);
    final header = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    expect(header.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(header.getUint16(22, Endian.little), 1, reason: 'one channel');
    expect(header.getUint32(24, Endian.little), 8000, reason: 'sample rate');
    expect(header.getUint16(34, Endian.little), 8, reason: 'bits per sample');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(header.getUint32(40, Endian.little), 3 * 8000);
    expect(wav.length, FakeAudio.headerBytes + 3 * 8000);
    expect(header.getUint32(4, Endian.little), wav.length - 8, reason: 'RIFF size is the file size minus 8');
  });

  test('the duration a player computes from the header is the one asked for', () {
    final wav = FakeAudio.wav(45);
    final header = ByteData.sublistView(wav);
    final seconds = header.getUint32(40, Endian.little) / header.getUint32(28, Endian.little);
    expect(seconds, 45);
  });

  test('is not silence, and does not clip', () {
    final wav = FakeAudio.wav(2);
    final samples = wav.sublist(FakeAudio.headerBytes);
    expect(samples.toSet().length, greaterThan(20), reason: 'a tune has many different levels');
    expect(samples.every((s) => s >= 0 && s <= 255), isTrue);
    // Quiet enough not to hurt: the loudest sample stays well inside the range.
    expect(samples.map((s) => (s - 128).abs()).reduce((a, b) => a > b ? a : b), lessThan(60));
  });

  test('different seeds make different tunes and the same seed the same one', () {
    expect(FakeAudio.wav(2, seed: 1), isNot(FakeAudio.wav(2, seed: 2)));
    expect(FakeAudio.wav(2, seed: 7), FakeAudio.wav(2, seed: 7));
  });

  test('the address is a data URI that decodes back to the WAV', () {
    final uri = FakeAudio.dataUri(2, seed: 3);
    expect(uri.scheme, 'data');
    expect(uri.toString(), startsWith('data:audio/wav;base64,'));
    final decoded = base64Decode(uri.toString().substring('data:audio/wav;base64,'.length));
    expect(decoded, FakeAudio.wav(2, seed: 3));
  });

  test('a 90 second track stays under a megabyte, small enough to keep in memory', () {
    expect(FakeAudio.wav(90).length, lessThan(1024 * 1024));
  });
}
