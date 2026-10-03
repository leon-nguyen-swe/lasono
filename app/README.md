# LaSono app

The Flutter web client for LaSono: upload a track, load it by id, play it and seek.

Run it from this folder (the backend and PostgreSQL must already be running):

```bash
flutter pub get
flutter run -d web-server --web-port 3000   # then open http://localhost:3000
flutter test
flutter analyze
```

The full setup (database, backend, configuration, troubleshooting) is in the [root README](../README.md).

## Code layout

- `lib/main.dart`: app entry point.
- `lib/api/track_api.dart`: HTTP calls to the backend (`API_BASE_URL` via `--dart-define`).
- `lib/models/`: data models.
- `lib/screens/`: `TrackScreen` (upload and load forms) and `PlayerControls` (play, seek).
- `lib/player_service.dart`: wrapper around `just_audio`.
- `lib/audio_picker.dart`: wrapper around `file_picker`.
