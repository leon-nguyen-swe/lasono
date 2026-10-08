import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/theme.dart';

/// A number made from [text] that is the same on every run, every platform and every version of Dart.
/// (`String.hashCode` is not: the browser and the phone may give different numbers for the same text.)
/// FNV-1a, 32 bits. Used to pick a colour from an id, so the same track or user always looks the same.
///
/// In a browser a Dart `int` is a JavaScript number, exact only up to 2^53. The usual `hash * prime` goes past that
/// and loses its low bits, which would give every id the same colour. So the product is made in two 16-bit halves,
/// and no number in it is ever larger than 2^41.
int stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit; // below 2^32, and unit is a 16-bit code unit
    hash = _times16777619(hash);
  }
  return hash;
}

// hash * 0x01000193 modulo 2^32. The prime is 0x0100 * 2^16 + 0x0193; the part that is multiplied by 2^32 is gone
// after the modulo, so only three small products are left.
int _times16777619(int hash) {
  final low = hash & 0xffff;
  final high = hash >> 16;
  final middle = (high * 0x0193 + low * 0x0100) % 0x10000;
  return (low * 0x0193 + middle * 0x10000) % 0x100000000;
}

/// The cover of a track: its image if it has one, otherwise a gradient made from the id of the track.
/// The same id always gives the same cover, so a track is recognised by its colours.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.trackId,
    this.imageUrl,
    this.size = 64,
    this.radius = AppRadius.md,
  });

  final String trackId;

  /// An address of an image; null when the track has none.
  final String? imageUrl;
  final double size;
  final double radius;

  /// The two colours of the gradient for [trackId].
  static (Color, Color) gradientFor(String trackId) =>
      AppGradients.cover[stableHash(trackId) % AppGradients.cover.length];

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = _Gradient(trackId: trackId, size: size);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: AppRadius.all(radius),
        child: SizedBox.square(
          dimension: size,
          child: url == null
              ? placeholder
              : Image.network(
                  url,
                  key: const Key('coverImage'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}

class _Gradient extends StatelessWidget {
  const _Gradient({required this.trackId, required this.size});

  final String trackId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hash = stableHash(trackId);
    final (from, to) = CoverArt.gradientFor(trackId);
    // The direction also depends on the id, so two covers with the same colours still look different.
    final angle = (hash >> 8) % 4 * (math.pi / 2) + math.pi / 4;
    return DecoratedBox(
      key: const Key('coverGradient'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(math.cos(angle), math.sin(angle)),
          end: Alignment(-math.cos(angle), -math.sin(angle)),
          colors: [from, to],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A big soft circle, off to one side: depth without a picture.
          Positioned(
            right: -size * 0.25,
            bottom: -size * 0.25,
            width: size * 0.9,
            height: size * 0.9,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.14)),
            ),
          ),
          if (size >= 40)
            Center(
              child: Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.85), size: size * 0.42),
            ),
        ],
      ),
    );
  }
}
