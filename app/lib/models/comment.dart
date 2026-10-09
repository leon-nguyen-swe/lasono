/// A comment pinned to a moment of a track.
class Comment {
  const Comment({
    required this.id,
    required this.trackId,
    required this.authorId,
    required this.positionMs,
    required this.text,
    this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        authorId: json['authorId'] as String,
        positionMs: (json['positionMs'] as num).toInt(),
        text: json['text'] as String,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  final String id;
  final String trackId;

  /// Only the id: the name comes from the user directory, as for the owner of a track.
  final String authorId;

  /// Where in the track the comment points, in milliseconds.
  final int positionMs;
  final String text;
  final DateTime? createdAt;
}

/// How comments are listed: by position (the markers on the waveform) or newest first (the list below it).
enum CommentOrder {
  position,
  recent;

  /// The value of the `order` query parameter.
  String get wireName => name;
}
