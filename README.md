# LaSono

A music streaming platform built with Flutter and Java Spring Boot, using a Modular Monolith and Clean Architecture.

Phase 1 lets you upload an MP3/WAV file, see its metadata, play it and seek inside it from a Flutter web app. The backend streams audio with HTTP `Range` support (`206 Partial Content`).

```
lasono/
├── backend/            Spring Boot 4 / Java 21 API (port 8080)
├── app/                Flutter web app (port 3000)
├── docs/               Plans and test records
└── docker-compose.yml  PostgreSQL 17 for local development
```

## Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| Java | 21 | Backend (Gradle wrapper is included) |
| Docker with Compose | recent | PostgreSQL |
| Flutter SDK | stable, Dart `^3.13.5` | Web app |
| Chrome | recent | Opening the app and DevTools |

## Run it locally

You need three things running at the same time, so use three terminals. Start them in this order.

### 1. Database

From the repository root:

```bash
docker compose up -d
```

PostgreSQL listens on `localhost:5432` (database, user and password are all `lasono`). Data lives in a Docker volume, so it survives restarts.
Stop it with `docker compose down`. **Do not add `-v`**, because that deletes the volume and every track.

### 2. Backend

The backend signs login tokens with a secret that is **not stored in the repository**. Set it once per terminal
(at least 32 bytes; the backend refuses to start with a shorter one):

```bash
export LASONO_JWT_SECRET="$(openssl rand -base64 48)"
```

A new secret signs out everyone who is logged in, so keep the same one while you develop.

```bash
cd backend
./gradlew bootRun
```

The API is now at `http://localhost:8080`. Flyway creates the tables on first start.
Uploaded audio files are stored in `backend/storage/audio/` (git-ignored).

### 3. Flutter web app

```bash
cd app
flutter pub get
flutter run -d web-server --web-port 3000
```

Then open **http://localhost:3000** in Chrome (the first start takes a minute while it compiles).

- Keep the port at **3000**: the backend only allows CORS requests from `http://localhost:3000` and `http://127.0.0.1:3000`.
- `-d web-server` just serves the app and does not launch a browser, which is what you want on WSL or a remote machine. On a normal desktop you can use `flutter run -d chrome --web-port 3000` instead.
- After you change Dart code, stop the app with `q` (or Ctrl+C) in that terminal, start it again, then refresh the page.

## Using the app

1. **Browse**: the app opens on the list of tracks, newest first. Scroll down and the next page loads by itself. If a page fails to load, press **Retry**.
2. **Play**: tap a track to open its player and press the play button. When a track finishes it rewinds to 0:00; press play again to replay it. Going back to the list stops the playback and keeps your place in the list.
3. **Seek**: drag or click the slider.
4. **Upload**: press the upload icon in the top bar, type a title, press **Choose file**, pick an `.mp3` or `.wav` (max 50 MB), press **Upload**. The new track loads automatically. When you go back, the list reloads and shows it.
5. **Load by id**: on the same upload screen, paste a track id and press **Load** to see a track that already exists.

## Configuration

| Setting | Where | Default |
|---------|-------|---------|
| Backend URL used by the app | `flutter run ... --dart-define=API_BASE_URL=http://host:8080` | `http://localhost:8080` |
| Allowed CORS origins | property `lasono.cors.allowed-origins` (comma separated) | `http://localhost:3000,http://127.0.0.1:3000` |
| Audio storage folder | property `lasono.storage.root` | `./storage/audio` (relative to where the backend starts) |
| Secret that signs login tokens | environment variable `LASONO_JWT_SECRET` (property `lasono.jwt.secret`), at least 32 bytes | none: the backend does not start without it |
| Lifetime of a login token | property `lasono.jwt.access-token-ttl` | `15m` |
| Upload size limit | `spring.servlet.multipart.max-file-size` / `max-request-size` in `backend/src/main/resources/application.yaml` | 50MB / 52MB |

Any Spring property can be overridden on the command line, for example:

```bash
./gradlew bootRun --args='--lasono.storage.root=/some/other/folder'
```

## API

All endpoints are under `/api/v1/tracks`.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/tracks` | Multipart form: `title`, optional `description`, `file`. Returns `201 {trackId, title, status}` with `status` `PROCESSING`; a background worker then converts the audio to MP3 and the track becomes `READY` (or `FAILED`). Errors: `415` unsupported audio type, `400` blank title or empty file, `413` file too large |
| `GET` | `/api/v1/tracks?limit=20&cursor=...` | Lists tracks newest first, one page at a time (keyset pagination). Returns `{items: [{id, title, description, status, durationSeconds}], nextCursor}` (`durationSeconds` is `null` until the track is `READY`); `nextCursor` is `null` on the last page, otherwise send it back as `cursor` to get the next page. `limit` defaults to 20 and is capped at 50. `400` for a malformed cursor or a `limit` below 1 |
| `GET` | `/api/v1/tracks/{id}` | Returns `{id, title, description, status, mimeType, durationSeconds, waveform}`; `waveform` is 200 peaks between 0 and 1, and `durationSeconds` and `waveform` are `null` until the track is `READY`. `404` if unknown, `400` if the id is not a UUID |
| `GET` | `/api/v1/tracks/{id}/stream` | Bytes of the converted MP3. `200` for a full read, `206` with `Content-Range` when a `Range` header is sent, `416` if the range is invalid, `409` if the track is not `READY` (still processing, or processing failed) |

Only `audio/mpeg` (MP3) and `audio/wav` / `audio/x-wav` (WAV) are accepted.

## Tests

```bash
cd backend && ./gradlew test          # backend tests (in-memory H2, no database needed)
cd backend && ./gradlew postgresTest  # backend tests that need a real PostgreSQL (see below)
cd backend && ./gradlew ffmpegTest    # backend tests that run the real ffmpeg and ffprobe (see below)
cd app && flutter test                # widget and unit tests
cd app && flutter analyze             # static analysis
```

`./gradlew test` also runs the architecture rules (ArchUnit, in `backend/src/test/java/com/lasono/architecture`): the domain must not depend on Spring, JPA, the file system or HTTP, and dependencies must point inward. GitHub Actions (`.github/workflows/ci.yml`) runs all of the above on every push and on pull requests into `main`.

### PostgreSQL tests

`postgresTest` runs the tests tagged `postgres` against a real PostgreSQL, because H2 does not behave exactly like PostgreSQL (migrations, indexes, timestamp precision). They use the separate database `lasono_test`, never `lasono`, and stop immediately if they are connected to any other database. Start PostgreSQL with `docker compose up -d` and create the test database once:

```bash
docker compose exec postgres psql -U lasono -d postgres -c "CREATE DATABASE lasono_test"
```

### ffmpeg tests

`ffmpegTest` runs the tests tagged `ffmpeg`. They call the real `ffmpeg` and `ffprobe` programs, so those must be installed (on Ubuntu or WSL: `sudo apt install ffmpeg`). The tests make their own audio files, so no audio is stored in the repository. The backend also needs both programs at runtime to process uploaded tracks; set `lasono.processing.ffmpeg-path`, `lasono.processing.ffprobe-path` or `lasono.processing.timeout-seconds` (default 300) in `application.yaml` if they are not on the `PATH`.

The end-to-end test among the `postgresTest` tests (upload, then the worker makes the track READY) also needs ffmpeg.

A background worker takes the processing jobs of uploaded tracks. It is on by default; `lasono.processing.worker-enabled=false` switches it off and `lasono.processing.poll-interval-ms` (default 2000) sets how often it looks for jobs. The tests of the other modules keep it off.

## Troubleshooting

| Symptom | Likely cause and fix |
|---------|----------------------|
| Upload sits at `(pending)` in DevTools, or the console says `Failed to fetch` | The backend you are running is missing the CORS filter or the 50MB upload limit (the Spring default is 1MB), so large files are rejected without a CORS header. Rebuild and restart the backend from the latest code. Check with `curl -i -H "Origin: http://localhost:3000" http://localhost:8080/api/v1/tracks/00000000-0000-0000-0000-000000000000`: the response must contain `Access-Control-Allow-Origin` |
| The app says `Cannot reach the server` | The backend is not running on `http://localhost:8080`, or the app was started with a different `API_BASE_URL` |
| Backend fails at startup with a connection error to PostgreSQL | Run `docker compose up -d` and wait a few seconds; confirm Docker is running |
| `flutter: command not found` | Add the SDK to your `PATH`, for example `export PATH="$HOME/development/flutter/bin:$PATH"` in `~/.bashrc`, then open a new terminal |
| `Port 3000 is already in use` | Stop the other process (`ss -ltnp \| grep 3000`) or the old `flutter run`; do not just switch ports because of CORS |
| A track plays no sound / `Cannot play this track` | The audio file for that track is missing from the storage folder (for example the database and `storage/` were reset separately) |
| `flutter pub get` or `flutter analyze` is very slow in WSL | The project is on a Windows drive (`/mnt/...`). Install the Flutter SDK on the Linux filesystem (for example `~/development/flutter`) |
| Every request to the backend sits at `(pending)` in Windows Chrome (even `Load` by id), but `curl` inside WSL answers instantly | The WSL "localhost forwarding" process (`wslrelay`) is stuck. See [Backend in WSL, browser on Windows](#backend-in-wsl-browser-on-windows) below |

### Backend in WSL, browser on Windows

When the backend runs in WSL and Chrome runs on Windows, Chrome reaches `localhost:8080` through `wslrelay`. That relay can get stuck, for example after a request that was aborted halfway. The symptom is that requests to the backend hang forever while the page itself (port 3000) still loads.

Confirm it from PowerShell on Windows: the first call hangs and the second answers immediately.

```powershell
Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 http://localhost:8080/api/v1/tracks/00000000-0000-0000-0000-000000000000
Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 http://<WSL-IP>:8080/api/v1/tracks/00000000-0000-0000-0000-000000000000
```

Get `<WSL-IP>` inside WSL with `hostname -I`. Both calls should return `404`; a timeout on the first one means the relay is stuck. Pick one fix:

1. **Restart WSL (quick).** In PowerShell run `wsl --shutdown`, then start Docker Desktop, the database, the backend and the app again. Data is kept because it lives in the Docker volume and in `backend/storage/`.
2. **Bypass the relay (no restart).** Start the app against the WSL address, for example:
   ```bash
   flutter run -d web-server --web-port 3000 --dart-define=API_BASE_URL=http://$(hostname -I | awk '{print $1}'):8080
   ```
   The WSL address changes when WSL restarts, so rerun the command then.
3. **Mirrored networking (permanent).** Create `%UserProfile%\.wslconfig` with the lines below, then run `wsl --shutdown`. This is Microsoft's documented option for Windows 11 22H2+ and makes `localhost` work in both directions without `wslrelay`. It was not tested in this repository.
   ```ini
   [wsl2]
   networkingMode=mirrored
   ```

The app also stops waiting after 30 seconds for `Load` ("Request timed out") and after 5 minutes for `Upload` ("Upload timed out"), so the form does not stay locked.

## More documentation

- `docs/lasono-phase1-flutter-plan.md`: the Phase 1 plan and the decisions behind it.
- `docs/phase1-e2e.md`: end-to-end verification results.
- `docs/core-audio-system-plan.md`: the backend design.
