import 'dart:typed_data';

import '../models/track.dart';
import '../models/track_page.dart';

/// Tracks: reading, uploading, changing and deleting them, and the address to play one.
/// Phase 1-4 of the backend; the real implementation is `TrackApi`.
abstract class TrackRepository {
  Future<Track> getTrack(String id);

  /// Newest first, one page at a time. Send the previous page's `nextCursor` to get the page after it.
  Future<TrackPage> listTracks({String? cursor, int? limit});

  /// The tracks of one user, newest first. The owner also gets the private ones.
  Future<TrackPage> listUserTracks(String userId, {String? cursor, int? limit});

  /// An address the audio player can open. The player cannot send the login header, so the server signs the
  /// permission into the address; ask for it just before playing.
  Future<Uri> fetchStreamUrl(String id);

  /// A field left null stays as it is; an empty [description] clears it.
  Future<Track> updateTrack(String id, {String? title, String? description, String? visibility});

  Future<void> deleteTrack(String id);

  /// Uploads an audio file and returns the id of the new track.
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  });
}
