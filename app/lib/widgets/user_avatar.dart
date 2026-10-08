import 'package:flutter/material.dart';

import 'cover_art.dart' show stableHash;

/// A person's picture: their image if there is one, otherwise their initials on a colour made from their id.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.displayName,
    this.imageUrl,
    this.size = 40,
  });

  final String userId;
  final String displayName;

  /// An address of an image; null when the user has none.
  final String? imageUrl;
  final double size;

  /// Colours dark enough for white letters on them (checked by the tests: at least 4.5:1).
  static const palette = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFFBE185D),
    Color(0xFF0F766E),
    Color(0xFFB45309),
    Color(0xFF1D4ED8),
    Color(0xFF15803D),
    Color(0xFFB91C1C),
  ];

  static Color colorFor(String userId) => palette[stableHash(userId) % palette.length];

  /// The letters shown: the first letter of the first word and of the last word. `Sơn Tùng` is `ST`,
  /// `Đen Vâu` is `ĐV`, a single name gives one letter, and nothing at all gives `?`.
  static String initialsOf(String displayName) {
    final words = displayName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    String first(String word) => String.fromCharCode(word.runes.first).toUpperCase();
    return words.length == 1 ? first(words.first) : first(words.first) + first(words.last);
  }

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      key: const Key('avatarInitials'),
      color: colorFor(userId),
      alignment: Alignment.center,
      child: Text(
        initialsOf(displayName),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontSize: size * 0.4,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
    final url = imageUrl;
    return Semantics(
      label: displayName,
      image: true,
      excludeSemantics: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: url == null
              ? initials
              : Image.network(url, key: const Key('avatarImage'), fit: BoxFit.cover, errorBuilder: (_, _, _) => initials),
        ),
      ),
    );
  }
}
