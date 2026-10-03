# LaSono Phase 1: Flutter Integration → Player → Seeking → E2E Plan

> Status: **DECIDED** (see section 3). Assumptions were checked against the real code in section 2.
> Scope: from the finished backend (Track Foundation → Storage hardening) until Phase 1 meets its "done-when".
> Conventions: documents, code, identifiers and commit/PR messages are all in English.

---

## 1. Goal and Definition of Done

**Phase 1 is done when**, in Flutter web, a user can:

1. Pick an audio file (MP3/WAV) and upload it.
2. See the metadata of the track just created (`GET /api/v1/tracks/{id}`).
3. Play the audio through `GET /api/v1/tracks/{id}/stream`.
4. Seek to any position, with the browser sending a `Range` request and the backend answering `206`.

**Out of scope**: auth, profile, like, comment, follow, playlist, feed, search, recommendation, Redis, Kafka, Elasticsearch, CDN, microservices, adaptive streaming, production object storage.

---

## 2. Current state and API contract (checked against the code)

### Already done (backend)
- Upload, Get Track, Streaming (200/206/416/404/400) and storage hardening are merged into `main`.
- Postgres volume confirmed: the 3 tracks in the DB match the 3 files in `storage/audio`.
- Flutter target: **web**, always served at `http://localhost:3000`.

### Actual API contract
| Endpoint | Details |
|----------|---------|
| Base URL | `http://localhost:8080` (no `server.port`, so the default 8080). `API_BASE_URL` does **not** contain `/api/v1`; the prefix is a constant in `TrackApi` |
| `POST /api/v1/tracks` | `multipart/form-data`: `title` (required), `description` (optional, defaults to empty), `file` (required). Returns **201** `{trackId, title, status}`. No `Location` header |
| `GET /api/v1/tracks/{id}` | Returns `{id, title, description, status, mimeType, durationSeconds}`. `durationSeconds` is **nullable** and always `null` until a processing pipeline exists |
| `GET /api/v1/tracks/{id}/stream` | 200 (no Range) / 206 (with Range) / 416 / 404 / 400 |
| List tracks | **None** |
| Accepted MIME types | `audio/mpeg` → MP3; `audio/wav`, `audio/x-wav` → WAV. The backend fully trusts the client's MIME type and does not sniff the content |
| CORS | None |
| Multipart limit | Not tuned: Spring defaults of 1MB/file and 10MB/request |

### Backend bugs found during review (fixed in Branch 2b)
- `TrackExceptionHandler` only mapped `TrackNotFound` and `InvalidRange`. `AudioFormatInvalidException` and `TrackTitleInvalidException` were unmapped, so they returned **500**.
- `UploadTrackUseCase` called `audioStorage.store(...)` **before** creating the `Track` (where the title is validated) and before `save`, so a blank title or a DB failure left an **orphan file**.
- Not yet checked: whether an empty file (size 0) is rejected by `OriginalAudio`, and whether that error is mapped.

---

## 3. Decisions

| Item | Decision |
|------|----------|
| Q1. Which track to play | **(a) + (b)**: the upload flow keeps `trackId` in state, plus a manual `trackId` input. No `GET /tracks` |
| Q2. Folder structure | Flat: `lib/main.dart`, `lib/api/`, `lib/models/`, `lib/screens/`; split only when it really hurts |
| Q3. HTTP client | `http` + `http_parser` (for `MediaType`). Upload progress bar later |
| Q4. State management | `setState` + plain Dart services. Cancel the player's subscriptions in `dispose()` |
| Q5. Mobile later | Base URL via `--dart-define=API_BASE_URL`, default `http://localhost:8080` |
| Flutter environment | Install the SDK in WSL (ext4, `~/development/flutter`), run `flutter run -d web-server --web-port 3000`, open it in Windows Chrome. First step: `flutter doctor` |
| Upload limit | **50MB/file, 52MB/request**, configured in yaml; Flutter uses a matching constant to fail early |
| Upload error codes | Wrong format → **415**; blank title → **400**; malformed UUID → 400 (handled by Spring); too large → 413 |

---

## 4. Known risks and how they are handled

| Risk | Consequence | Handling |
|------|-------------|----------|
| **CORS** not configured | The browser blocks reading the response (multipart upload and JSON GET are *simple requests* with no preflight, but a response without `Access-Control-Allow-Origin` is still blocked) | Branch 2: `CorsFilter` (a servlet filter, so early errors also carry the headers); origins come from a property and allow both `localhost:3000` and `127.0.0.1:3000` (they are different origins) |
| **413 without CORS headers** | Spring throws `MaxUploadSizeExceededException` before reaching the handler; Flutter would only see a generic network error | A client-side size check before sending is the main guard; test whether `CorsFilter` also covers the 413 |
| **Part `Content-Type`** | `MultipartFile.fromBytes` defaults to `application/octet-stream`, which the backend rejects (it used to return 500) | Always set `contentType` from the extension: `audio/mpeg` for mp3, `audio/wav` for wav |
| **Flutter web has no file path** | `file_picker` on web has no path | Use `PlatformFile.readAsBytes()` (file_picker 13 dropped `withData`) + `MultipartFile.fromBytes`; a 50MB cap keeps tab RAM reasonable |
| **Seeking does not work** even though the backend returns 206 correctly | The seek does nothing or jumps to the start | Check `Accept-Ranges: bytes`, `Content-Type`, `Content-Length`/`Content-Range`; DevTools → Network. Chrome always sends `Range: bytes=0-`, so a 206 is normally seen from the first request |
| **Browser cancels the old request when seeking** | The backend may log an error/500 when the client disconnects midway | Branch 6: check the backend log while seeking repeatedly |
| **MP3 VBR** | Duration/seek estimated wrongly in some browsers | Test both CBR and VBR if available; record it as a limitation |
| **Track stuck in `PROCESSING`** | A UI gated on `status` would never play | The UI does **not** gate on `status`; the backend already falls back to `OriginalAudio` |
| **Chrome autoplay policy** | Autoplay after upload is blocked | Only start playback when the user presses the button |
| **A real `.txt` renamed `.mp3`** | The backend accepts it because it only trusts the MIME type | Known Phase 1 limitation; recorded in the E2E |
| **`StreamingResponseBody` on the default executor** | Can congest with many parallel streams | Later; Phase 1 has a single user |
| **Relative storage path** (`./storage/audio`) | Running from `backend/` puts files in `backend/storage/audio` | The E2E checklist states the real path |
| **Slow Flutter toolchain with the repo on `/mnt/d`** | Slow `pub get`/analyze | SDK lives on ext4; revisit if it is too slow |

---

## 5. Plan by branch

Workflow for every branch (unchanged):
`new branch → code → test → commit → verify for real in the browser/HTTP → PR → merge/rebase (no squash)`

### Branch 1: `feat/flutter-init` (~1 hour)
**Goal:** a Flutter web app running on port 3000.
- Install the Flutter SDK into `~/development/flutter`, add it to `PATH`, run `flutter doctor`.
- `flutter create --platforms=web --project-name lasono_app app` inside `/mnt/d/lasono`
- `flutter run -d web-server --web-port 3000`
- Reduce `main.dart` to a minimal screen ("LaSono"), remove the counter demo; **delete/rewrite the sample `test/widget_test.dart`** so `flutter test` does not fail.
- **Verify:** Chrome shows the minimal screen at `http://localhost:3000`; `flutter analyze` and `flutter test` are clean.
- **Commit:** `chore: scaffold Flutter web project`

### Branch 2: `feat/backend-cors-dev` (~1 hour, **backend**)
**Goal:** Flutter web can call the backend.
- Add a `CorsFilter` bean in the Presentation/Infrastructure layer, **without** touching Domain/Application. Origins come from `lasono.cors.allowed-origins` (a list, default `http://localhost:3000,http://127.0.0.1:3000`); methods `GET, POST, OPTIONS`; expose `Content-Range`, `Accept-Ranges`, `Content-Length`; applies to `/api/**`.
- `MockMvc` tests: `GET`/`POST` with `Origin: http://localhost:3000` return `Access-Control-Allow-Origin`; an unknown origin does not; the `OPTIONS` preflight still works.
- **Real verification:**
  ```bash
  curl -i http://localhost:8080/api/v1/tracks/<id> -H "Origin: http://localhost:3000"
  curl -i -X OPTIONS http://localhost:8080/api/v1/tracks \
    -H "Origin: http://localhost:3000" \
    -H "Access-Control-Request-Method: POST"
  ```
- **Commit:** `feat: allow CORS for Flutter web origins`

### Branch 2b: `fix/upload-validation` (~1.5 hours, **backend**, NEW)
**Goal:** failed uploads return the right status and leave no orphan file. **Write the tests first (TDD).**
- `TrackExceptionHandler`: `AudioFormatInvalidException` → 415; `TrackTitleInvalidException` → 400 (same `ProblemDetail` style as today). Check, and map, the empty-file error if `OriginalAudio` throws it.
- `UploadTrackUseCase`: create the `Track` (title validation) **before** `store`; if `trackRepository.save` fails, call `audioStorage.delete(key)`.
- `application.yaml`: `spring.servlet.multipart.max-file-size: 50MB`, `max-request-size: 52MB`.
- Tests: use-case tests (blank title → no file in the storage fake; save failure → file deleted); `TrackControllerTest` (415, 400).
- **Real verification:** curl an upload of a `.txt` (415), a blank title (400, no new file in storage), a file > 50MB (413).
- **Commit:** `fix: map upload validation errors to 415 and 400`

### Branch 3: `feat/flutter-get-track` (~1.5 hours)
**Goal:** Flutter calls `GET /api/v1/tracks/{id}` and shows the metadata.
- `pubspec`: add `http`.
- `lib/models/track.dart`: `fromJson` matching the 6 fields of `GetTrackResult`; `durationSeconds` is nullable.
- `lib/api/track_api.dart`: takes a `baseUrl` (`--dart-define=API_BASE_URL`, default `http://localhost:8080`); the `/api/v1` prefix is a constant.
- Error handling: 404 → "Track not found", 400 → "Invalid id", network error → a generic message.
- UI: a `trackId` input + a "Load" button + display of `title`, `description`, `status`.
- **Tests:** Dart unit test for `Track.fromJson` (sample JSON taken with curl from a real response); `TrackApi` tests with `MockClient`.
- **Real verification:** enter the id of the "Vietnamese" track in the DB and see the right metadata; enter a wrong id and see the error.
- **Commit:** `feat: load a track by id on TrackScreen`

### Branch 4: `feat/flutter-upload` (~2 hours)
**Goal:** pick a file, upload it, receive the `trackId`.
- `pubspec`: add `file_picker`, `http_parser`.
- `FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['mp3', 'wav'])` then `await file.readAsBytes()` (file_picker 13 API; `withData` and `FilePicker.platform` no longer exist).
- `http.MultipartRequest('POST', .../api/v1/tracks)`: fields `title`, `description`, and `MultipartFile.fromBytes('file', bytes, filename: ..., contentType: <audio/mpeg | audio/wav by extension>)`.
- On 201 → read `trackId` (not `id`) and run the get-track flow (Branch 3). On 4xx → show the reason (415, 400, 413).
- Client-side guards: file > 50MB (constant matching the backend), blank title.
- **Real verification:**
  1. Upload a real MP3 from the UI → see the `trackId` + metadata.
  2. `storage/audio` gains exactly one `<uuid>.mp3` file and the DB gains one row.
  3. Upload a wrong-format file / blank title / oversized file → a clear error, and the DB and storage gain **nothing**.
- **Commit:** `feat: add upload form to TrackScreen`

### Branch 5: `feat/flutter-player` (~2 hours)
**Goal:** play audio through `/stream`.
- `pubspec`: add `just_audio`.
- A `PlayerService` wrapping `AudioPlayer`; `setUrl('$baseUrl/api/v1/tracks/$id/stream')`.
- UI: Play/Pause, show `position` / `duration` (from the player's streams, not the API's `durationSeconds`).
- Handle load errors and a loading state; `dispose()` cancels the player/subscriptions.
- **Real verification:** upload, press Play and hear it; DevTools → Network shows the `stream` request returning `206` (or `200`) with the right `Content-Type`.
- **Commit:** `feat: play tracks from TrackScreen`

### Branch 6: `feat/flutter-seeking` (~1.5 hours)
**Goal:** seeking works and the backend returns the right 206.
- A `Slider` wired to `player.seek(...)`; only draggable once a `duration` is known.
- **Real verification (the most important one in Phase 1):**
  1. DevTools → Network, filter `stream`.
  2. Drag the slider to the middle → a new request with `Range: bytes=<start>-`, response `206` + correct `Content-Range`.
  3. Listen: the sound jumps to the right position and does not restart from the beginning.
  4. Drag to the start, then to the end → no error, no hang.
  5. Repeat with both MP3 and WAV.
  6. Watch the backend log while seeking repeatedly: no 500/stack trace caused by client disconnects.
- **Commit:** `feat: add seek slider to player controls`

### Branch 7: `test/phase1-e2e` (~1.5 hours)
**Goal:** prove Phase 1 meets its done-when, and document it.
- Run the E2E checklist (section 6) with a clean DB + clean storage.
- Record the results in `docs/phase1-e2e.md` (pass/fail table + Network tab screenshots).
- (Optional) a `curl` script that checks the backend contract (upload/get/200/206/416).
- **Commit:** `docs: record Phase 1 end-to-end verification`

> **Total estimate:** about **13–15 hours** of real work (including the SDK install and Branch 2b), not counting CORS/seek debugging.

---

## 6. Phase 1 E2E checklist

| # | Scenario | Expected result |
|---|----------|-----------------|
| 1 | Upload a valid MP3 | A `trackId`; 1 `<uuid>.mp3` file in storage; 1 row in the DB |
| 2 | Upload a valid WAV | Same, with a `.wav` extension |
| 3 | Upload a file name containing `../` or Vietnamese diacritics/spaces | Succeeds; the key is still `<uuid>.<ext>` (the backend does not use the original file name) |
| 4 | Upload a file of the wrong format | 415, nothing written |
| 5 | Upload a file over 50MB | A clear error (blocked on the client; calling the backend directly returns 413), nothing written |
| 6 | Get an existing track id | Correct metadata (6 fields) |
| 7 | Get a non-existent / malformed track id | 404 / 400 |
| 8 | Play from the start | Audible, `stream` request returns 206 (or 200) |
| 9 | Seek to the middle | The request has `Range`, returns `206`, sound at the right position |
| 10 | Seek to the end / back to the start | No error, no hang |
| 11 | Reload the page and re-enter the id | Still plays (data is durable) |
| 12 | Restart the backend + Postgres container (**not** `down -v`) | Old tracks still play (the volume is durable) |
| 13 | Upload with a blank title | 400, no file added to storage |
| 14 | Upload a `.txt` renamed to `.mp3` | The backend accepts it (it only trusts the MIME type); recorded as a known limitation |
| 15 | Unknown origin (curl `Origin: http://evil.example`) | The response has no `Access-Control-Allow-Origin` |

---

## 7. Working principles

- Each branch does **one** thing; the commit message matches exactly what changed.
- Commit messages are `type: summary` with no scope. Commit small, per file or per small group of related files, one line each, never one commit for everything.
- Automated tests are not enough: always verify in the real browser/HTTP before calling something done (`@TempDir` and `MockClient` can both hide infrastructure bugs).
- The backend only changes in Branch 2 (CORS) and 2b (upload bug fix + size limit); otherwise it stays frozen.
- Do not add libraries, state management or package structure before it really hurts.
- Do not guess field names/signatures: read the code first, and if an assumption is unavoidable, record it in section 2.

---

## 8. After Phase 1 (not committed, direction only)

- A dedicated `TaskExecutor` for `StreamingResponseBody`.
- Upload progress bar (consider `dio`).
- A list-tracks endpoint if Phase 2 needs it.
- Check the real file content (magic bytes) instead of only trusting the MIME type.
- Run on Android/iOS (base URL `10.0.2.2`, cleartext HTTP).
