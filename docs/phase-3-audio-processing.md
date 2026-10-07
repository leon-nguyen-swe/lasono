# Phase 3: Audio processing pipeline

## Goal
An uploaded track must become something the app can play and draw: the server converts the audio to a streaming MP3, reads its duration and builds a waveform, all in the background, and the app shows the progress. Before this phase an upload was streamed as it came (a 10 MB WAV, no duration, no waveform).

## What works now
Upload returns `201` at once with `status: PROCESSING`. A background worker then makes the track `READY` (MP3 128 kbps, `durationSeconds`, 200 waveform peaks), or `FAILED` after three attempts. The app shows a status badge and the duration, polls a processing track every 3 seconds, draws the waveform and seeks when it is tapped. Only a `READY` track can be streamed (`409` otherwise).

## End-to-end check (2026-10-07)
Real backend (`./gradlew bootRun`), PostgreSQL 17 in Docker (dev database `lasono`, migration V3 applied by Flyway), real ffmpeg, worker on with the default 2 s poll. Driven with `curl`.

| # | Scenario | Result |
|---|----------|--------|
| 1 | Upload a 5 s stereo WAV (861 KB) | `201`, `status: PROCESSING` |
| 2 | `GET /tracks/{id}` right after the upload | `PROCESSING`, `durationSeconds` and `waveform` are `null` |
| 3 | `GET /tracks/{id}/stream` while processing | `409` |
| 4 | Wait | `READY` about 2 s after the upload |
| 5 | `GET /tracks/{id}` when ready | `mimeType: audio/mpeg`, `durationSeconds: 5.0`, 200 waveform samples between 0 and 1 |
| 6 | Stream the MP3 | `200`, `Content-Type: audio/mpeg`, 81,128 bytes (5 s at 128 kbps is about 80 KB), `Accept-Ranges: bytes` |
| 7 | Stream with `Range: bytes=0-99` | `206`, `Content-Range: bytes 0-99/81128` |
| 8 | List | The item has `durationSeconds: 5.0` |
| 9 | Upload 2 KB of random bytes as `audio/wav` | `PROCESSING`, then `FAILED` after 95 s (attempts at once, +30 s, +60 s); stream answers `409`; the job row is `FAILED`, `attempts = 3`, `last_error` names the ffprobe failure |
| 10 | Leftovers | No `lasono-audio-*` temporary directory is left behind |

The Flutter UI was then tried in a real browser by the project owner (2026-10-07): two real files were uploaded and both became `READY`, and the track list showed the duration with the `READY` badge, the hourglass with `PROCESSING` and a red `FAILED` (the corrupt file from the check above). The waveform drawing and seeking inside the player are covered by widget tests (106, against a fake server); they have not been confirmed by eye yet.

Automated tests at the end of the phase: 265 backend tests, 40 `postgresTest`, 7 `ffmpegTest`, 106 Flutter tests, 0 failures. `postgresTest` includes an end-to-end test (upload, then the worker makes the track READY) with a real PostgreSQL and a real ffmpeg.

## Key design decisions and why
| Decision | Why |
|----------|-----|
| The job queue is a table in PostgreSQL, not Redis or Kafka | One database already exists, and the job is added in the **same transaction** as the track, so a track never exists without its job (or the reverse). A broker would add a second system and a "saved but not queued" gap. |
| A worker claims a job with one `UPDATE ... WHERE id = (SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING` | Several workers can run at once and never take the same job: a locked row is skipped, not waited for. |
| The attempt is counted when the job is claimed, and a claim leases the job (`locked_until`) | A worker that dies still used an attempt, so a poisonous file cannot loop forever. When the lease expires another worker may take the job. The database clock (`now()`) decides every time comparison. |
| A failed attempt is retried after 30 s, then 60 s; after the last attempt the track becomes `FAILED` | Short hiccups (disk, memory) heal by themselves, and a corrupt file ends in a visible state instead of `PROCESSING` forever. A `READY` track is never marked `FAILED`. |
| A reaper (`failExhausted`) fails jobs that are `RUNNING`, expired and out of attempts | Without it a job whose worker died on every attempt stayed `RUNNING` and its track `PROCESSING` forever. |
| `complete` and `fail` only work if `attempts` still equals the claimed attempt (`LEASE_LOST` otherwise) | A slow worker whose lease expired must not overwrite the result of the worker that took the job over. |
| `ProcessTrackUseCase` skips a track that is not `PROCESSING`, and `PROCESSING` of the audio resource is only held in memory | A retry (or a crash after saving but before reporting) starts from the same state and changes nothing the second time. |
| The heavy work (ffmpeg) runs outside any database transaction | A 30 s conversion must not hold a connection and a transaction open. |
| ffmpeg is called with an argument list, output redirected to files, a timeout, `destroyForcibly` and an exit code check | No shell, so a file name cannot inject a command; pipes that nobody reads cannot block the process; a hung ffmpeg cannot hang the worker. |
| Waveform: mono 8 kHz signed 16-bit PCM, 200 peaks; streaming format: MP3 128 kbps | Small and cheap to draw; MP3 plays in every browser and keeps Range requests simple. |
| The waveform is returned by `GET /tracks/{id}` only; the list carries just `durationSeconds`, read with one extra query per page | 200 numbers for each of 20 to 50 tracks would bloat the list; one query per page avoids N+1. |
| Only the converted MP3 is streamed and a track that is not `READY` answers `409` | The original upload can be a huge WAV, or a corrupt file after a failure. This changed the Phase 1 behaviour (which played the original). |
| The worker is a `@Scheduled` component switched with `lasono.processing.worker-enabled`, and `runAllDue()` drains every due job per tick | Tests must not have a background thread taking jobs; draining avoids a backlog of one job per poll. |
| Tests use hand-written fakes (no Mockito for the new code); `postgresTest` stays instead of Testcontainers | Fakes show the behaviour, not the call sequence. Testcontainers was dropped on purpose: a local Docker container plus a tagged Gradle task was enough (this closes the Testcontainers item of the plan). |
| The app marks `PROCESSING` with a still hourglass, polls only on the player screen, and fetches the waveform once for a `READY` track that came from the list | A spinner animates forever (tiring in a list, and `pumpAndSettle` never settles); polling the whole list every 3 s would be N requests; the list does not carry the waveform. |

## Pitfalls found
- **Two workers took the same job** with `UPDATE ... WHERE id = (SELECT ...)`. The `SELECT` ran before the lock, so both chose the same id. Fix: `FOR UPDATE SKIP LOCKED` in the `SELECT` (see `learning-log.md`).
- **Foreign key error after adding `@Transactional`.** Hibernate delays its `INSERT` to flush time, but `JdbcTemplate` wrote the job straight away. Fix: `saveAndFlush` (see `learning-log.md`).
- **A slow worker overwriting the job of the worker that took over.** Fixed by fencing with `attempts` (see `learning-log.md`).
- **An in-memory fake that kept the same object** hid bugs: a change that was never saved was visible to the next read. The fake repository now returns copies, like a database.
- **A background worker inside a cached Spring test context** keeps running after its test class and would take the jobs of other tests that share the database. The end-to-end test uses `@DirtiesContext`.
- **ffprobe prints `N/A` for a zero-length WAV**, which broke number parsing. It is now reported as an `AudioProcessingException`.
- **Mixing stereo to mono lowers the amplitude** of a sine wave, so a test threshold taken from the source level was wrong (checked with a mutation).
- **Gradle reports a test task as up to date**, so a repeated run proves nothing; use `--rerun`.
- **Docker Desktop must be running** for `postgresTest`; otherwise the tests fail with a connection error, which is not a real RED.

## Known limits
- Tracks created before this phase have no job. In a database that already has them they stay `PROCESSING` and cannot be streamed (the planned backfill migration was skipped on purpose).
- A permanent error (a corrupt file) uses all three attempts, so the user waits about 95 s to see `FAILED`.
- The original upload is kept after processing; it is never deleted.
- The app does not refresh the track list by itself; only the player screen polls. If the first waveform request fails, it is not retried until the track is opened again.
- The format check trusts the MIME type sent by the client; a wrong file becomes `FAILED` after the attempts.
- A track from Phase 1 or 2 stays `PROCESSING` in the list for good (seen in the real list as the oldest entry); there is no job for it.
