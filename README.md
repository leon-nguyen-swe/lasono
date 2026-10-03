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

1. **Upload**: type a title, press **Choose file**, pick an `.mp3` or `.wav` (max 50 MB), press **Upload**. The new track loads automatically.
2. **Load by id**: paste a track id and press **Load** to see a track that already exists.
3. **Play**: press the play button. When a track finishes it rewinds to 0:00; press play again to replay it.
4. **Seek**: drag or click the slider.

## Configuration

| Setting | Where | Default |
|---------|-------|---------|
| Backend URL used by the app | `flutter run ... --dart-define=API_BASE_URL=http://host:8080` | `http://localhost:8080` |
| Allowed CORS origins | property `lasono.cors.allowed-origins` (comma separated) | `http://localhost:3000,http://127.0.0.1:3000` |
| Audio storage folder | property `lasono.storage.root` | `./storage/audio` (relative to where the backend starts) |
| Upload size limit | `spring.servlet.multipart.max-file-size` / `max-request-size` in `backend/src/main/resources/application.yaml` | 50MB / 52MB |

Any Spring property can be overridden on the command line, for example:

```bash
./gradlew bootRun --args='--lasono.storage.root=/some/other/folder'
```

## API

All endpoints are under `/api/v1/tracks`.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/tracks` | Multipart form: `title`, optional `description`, `file`. Returns `201 {trackId, title, status}`. Errors: `415` unsupported audio type, `400` blank title or empty file, `413` file too large |
| `GET` | `/api/v1/tracks/{id}` | Returns `{id, title, description, status, mimeType, durationSeconds}`. `404` if unknown, `400` if the id is not a UUID |
| `GET` | `/api/v1/tracks/{id}/stream` | Audio bytes. `200` for a full read, `206` with `Content-Range` when a `Range` header is sent, `416` if the range is invalid |

Only `audio/mpeg` (MP3) and `audio/wav` / `audio/x-wav` (WAV) are accepted.

## Tests

```bash
cd backend && ./gradlew test        # backend unit and slice tests
cd app && flutter test              # widget and unit tests
cd app && flutter analyze           # static analysis
```

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
