import '../api/profile_api.dart';
import 'track.dart';

/// What a search can be asked for.
enum SearchType {
  all,
  tracks,
  users;

  String get wireName => name;
}

class SearchResults {
  const SearchResults({this.tracks = const [], this.users = const []});

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        tracks: (json['tracks'] as List<dynamic>? ?? const [])
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList(),
        users: (json['users'] as List<dynamic>? ?? const [])
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final List<Track> tracks;
  final List<Profile> users;

  bool get isEmpty => tracks.isEmpty && users.isEmpty;
}
