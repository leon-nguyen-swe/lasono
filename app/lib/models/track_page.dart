import 'track.dart';

/// One page of a list of tracks. [nextCursor] is null on the last page; otherwise send it back to get the
/// page after this one. [totalCount] is only sent for the tracks of one user (how many the viewer may see).
class TrackPage {
  const TrackPage({required this.items, this.nextCursor, this.totalCount});

  factory TrackPage.fromJson(Map<String, dynamic> json) {
    return TrackPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      totalCount: (json['totalCount'] as num?)?.toInt(),
    );
  }

  final List<Track> items;
  final String? nextCursor;
  final int? totalCount;
}
