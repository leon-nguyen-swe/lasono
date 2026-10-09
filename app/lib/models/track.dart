class Track {
  const Track({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.ownerId = '',
    this.visibility = 'PUBLIC',
    this.mimeType,
    this.durationSeconds,
    this.waveform,
    this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLikedByMe = false,
    this.coverUrl,
  });

  /// Reads a track from the server. The fields added in Phase 5 (`createdAt`, `likeCount`, `commentCount`,
  /// `isLikedByMe`, `coverUrl`) may be missing, because the backend of Phase 1-4 does not send them: they
  /// then get a neutral value, and the app keeps working.
  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      status: json['status'] as String,
      ownerId: json['ownerId'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'PUBLIC',
      mimeType: json['mimeType'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
      waveform: (json['waveform'] as List<dynamic>?)
          ?.map((peak) => (peak as num).toDouble())
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      isLikedByMe: json['isLikedByMe'] as bool? ?? false,
      coverUrl: json['coverUrl'] as String?,
    );
  }

  final String id;
  final String title;
  final String description;
  final String status;

  /// The user who uploaded the track.
  final String ownerId;

  /// `PUBLIC` or `PRIVATE`: a private track is seen only by its owner.
  final String visibility;
  final String? mimeType;
  final double? durationSeconds;

  /// Peaks between 0 and 1 to draw the waveform; null until the track is READY.
  final List<double>? waveform;

  /// When the track was created (UTC); null when the server does not say.
  final DateTime? createdAt;
  final int likeCount;
  final int commentCount;

  /// Whether the logged-in user liked the track; false when nobody is logged in.
  final bool isLikedByMe;

  /// An address of a cover image; null when the track has none (the app draws a placeholder).
  final String? coverUrl;

  bool get isReady => status == 'READY';
  bool get isPrivate => visibility == 'PRIVATE';

  /// The length in milliseconds, which is what a comment position is measured against.
  int? get durationMs => durationSeconds == null ? null : (durationSeconds! * 1000).round();

  Track copyWith({
    String? title,
    String? description,
    String? status,
    String? visibility,
    String? mimeType,
    double? durationSeconds,
    List<double>? waveform,
    int? likeCount,
    int? commentCount,
    bool? isLikedByMe,
  }) =>
      Track(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        status: status ?? this.status,
        ownerId: ownerId,
        visibility: visibility ?? this.visibility,
        mimeType: mimeType ?? this.mimeType,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        waveform: waveform ?? this.waveform,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        isLikedByMe: isLikedByMe ?? this.isLikedByMe,
        coverUrl: coverUrl,
      );
}
