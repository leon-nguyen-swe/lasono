# LaSono Phase 1: End-to-End Verification Results

> Run date: 2026-10-03. The checklist comes from section 6 of `lasono-phase1-flutter-plan.md`.
> Environment: Spring Boot backend (`feat/backend-cors-dev` + `fix/upload-validation` merged) + Postgres 17 (Docker, existing volume) + storage at `backend/storage/audio`; Flutter web frontend at `localhost:3000` (Chrome, DevTools → Network).
> Result sources: **curl** = automated real HTTP calls against the backend; **UI** = manual interaction in Chrome by the user.

## Results

| # | Scenario | Result | Source | Notes |
|---|----------|--------|--------|-------|
| 1 | Upload a valid MP3 | PASS | curl + UI | 201 `{trackId,title,status}`; storage 3 → 4 files; the UI upload succeeded and the new track played |
| 2 | Upload a valid WAV | NOT RUN | | Nobody has tried a `.wav` file yet |
| 3 | File name with `../` and Vietnamese diacritics | PASS | curl | `filename=../../Thầy Năm.mp3` → 201, stored as `<uuid>.mp3` |
| 4 | Upload a file of the wrong format | PASS | curl + UI | Backend: `application/octet-stream` → 415, storage unchanged. UI: a `.pdf` was blocked with "Only MP3 and WAV files are supported" |
| 5 | Upload a file over 50MB | PASS (backend) | curl | 51 MiB → 413, **the response still carries `Access-Control-Allow-Origin`**, storage unchanged. The client-side guard is only covered by a unit test, not tried by hand |
| 6 | Get an existing track id | PASS | curl + UI | All 6 fields; the UI shows title/description/status |
| 7 | Get a non-existent / malformed track id | PASS (backend) | curl | 404 / 400, both with CORS headers. The "Track not found"/"Invalid id" messages in the UI are only covered by a widget test |
| 8 | Play from the start | PASS | UI | The `stream` request returned **206**, `Content-Type: audio/mpeg`, `Accept-Ranges: bytes`, `Content-Range: bytes 0-130943/130944` |
| 9 | Seek to the middle | PASS (audio) | UI + curl | The sound jumped to the right place. The backend returned a correct 206 for `Range: bytes=1000-1999` (1000 bytes). **A second Range request from the browser was not observed**: the test file is only 128 KB, so Chrome had already loaded all of it in the first request |
| 10 | Seek to the end / back to the start | PASS after fix | UI | Two bugs were found at first (see below); fixed and confirmed OK by the user |
| 11 | Reload the page and re-enter the id | NOT RUN | | |
| 12 | Restart backend + Postgres (not `down -v`) | NOT RUN | | Postgres kept the 3 original tracks across this Docker Desktop restart (3 DB rows match 3 files) |
| 13 | Upload with a blank title | PASS | curl + UI | Backend: 400 `Track title must not be blank`, storage unchanged. UI: "Enter a title" |
| 14 | Upload a `.txt` renamed to `.mp3` | NOT RUN | | Known limitation: the backend only trusts the MIME type |
| 15 | Unknown origin | PASS | curl | `Origin: http://evil.example` → 403, no `Access-Control-Allow-Origin`; a preflight from the allowed origin → 200 |

Extra (outside the checklist): an empty file → 400 `File size must be greater than 0`, storage unchanged; a Range beyond the file → 416 with `Content-Range: bytes */130944`.

## Bugs found during manual testing (fixed)

| Symptom | Cause | Fix |
|---------|-------|-----|
| After a track played to the end, seeking made no sound until Pause then Play | `just_audio` keeps `playing = true` after the end, so the button still showed Pause and seeking did not restart playback | On completion: pause, rewind to 0:00 and show the Play button again |
| After an upload, the slider kept showing the previous track's duration until Play was pressed | `just_audio`'s `duration`/`position` streams replay their latest value to new subscribers | Subscribe only after the new track has finished loading |

## Known limitations

- The backend only trusts the MIME type sent by the client and does not inspect the file content (magic bytes).
- Large files are only checked against the 50MB limit; Flutter web reads the whole file into tab RAM.
- `JustAudioPlayerService` (the `just_audio` wrapper) was only verified by hand and has no automated test.
- The dev data has 2 extra tracks from this run: "E2E mp3" and "traversal".

## Still to do to close Phase 1

- Run the NOT RUN rows (#2, #11, #12, #14).
- Seek on a larger file (a few MB or more) to see the second `Range: bytes=<start>-` request in the Network tab, since that is done-when condition 4.
