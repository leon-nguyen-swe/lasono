class Track {
  const Track({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.mimeType,
    this.durationSeconds,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      status: json['status'] as String,
      mimeType: json['mimeType'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String title;
  final String description;
  final String status;
  final String? mimeType;
  final double? durationSeconds;
}
