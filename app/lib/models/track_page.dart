import 'track.dart';

/// One page of GET /api/v1/tracks. [nextCursor] is null on the last page;
/// otherwise send it back to get the page after this one.
class TrackPage {
  const TrackPage({required this.items, this.nextCursor});

  factory TrackPage.fromJson(Map<String, dynamic> json) {
    return TrackPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<Track> items;
  final String? nextCursor;
}
