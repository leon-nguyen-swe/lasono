import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Sound for the fake tracks, so that a fake track can really be played (and seeked) without any file.
///
/// It makes a WAV in memory: 8 kHz, one channel, 8 bits, a soft arpeggio whose notes depend on a seed, so
/// different tracks sound different. 8 bits at 8 kHz is 8 KB per second, small enough to put in an address.
abstract final class FakeAudio {
  static const sampleRate = 8000;
  static const headerBytes = 44;

  // A pentatonic scale in Hz: any order of these sounds fine.
  static const _scale = [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25];

  /// The WAV file for [seconds] of sound.
  static Uint8List wav(int seconds, {int seed = 0}) {
    final samples = seconds * sampleRate;
    final bytes = ByteData(headerBytes + samples);

    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 36 + samples, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // size of the fmt part
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // one channel
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate, Endian.little); // bytes per second: 1 byte x 1 channel x rate
    bytes.setUint16(32, 1, Endian.little); // bytes per sample frame
    bytes.setUint16(34, 8, Endian.little); // bits per sample
    text(36, 'data');
    bytes.setUint32(40, samples, Endian.little);

    const noteSeconds = 0.5;
    for (var i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final note = (t ~/ noteSeconds + seed * 3) % _scale.length;
      final frequency = _scale[note] * (1 + (seed % 3) * 0.25);
      // Each note fades in and out so there is no click between two of them.
      final inNote = (t % noteSeconds) / noteSeconds;
      final envelope = sin(pi * inNote);
      final value = sin(2 * pi * frequency * t) * envelope * 0.35;
      // 8-bit WAV is unsigned: silence is 128.
      bytes.setUint8(headerBytes + i, (128 + value * 127).round().clamp(0, 255));
    }
    return bytes.buffer.asUint8List();
  }

  /// The same WAV as an address the audio player can open.
  static Uri dataUri(int seconds, {int seed = 0}) =>
      Uri.parse('data:audio/wav;base64,${base64Encode(wav(seconds, seed: seed))}');
}
