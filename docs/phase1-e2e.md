# LaSono Phase 1: End-to-End Verification Results

> Run date: 2026-10-03. The checklist comes from section 6 of `lasono-phase1-flutter-plan.md`.
> Environment: Spring Boot backend (CORS filter + upload validation + 50MB limit) + Postgres 17 (Docker, existing volume) + storage at `backend/storage/audio`; Flutter web app (debug build) at `localhost:3000`.
> Real files used: `M500001ZXejr2Lr8cc.mp3` (4,005,908 bytes, ID3 tag) and `file_example_WAV_10MG.wav` (10,544,134 bytes, RIFF/WAVE, 59.77 s).
> Result sources:
> - **curl**: scripted real HTTP calls against the backend.
> - **Browser**: the real Flutter web UI driven in headless Chromium 153 (Playwright), with every request to the backend logged.
> - **Manual**: the user's own testing in Chrome.

## Results

| # | Scenario | Result | Source | Notes |
|---|----------|--------|--------|-------|
| 1 | Upload a valid MP3 | PASS | curl + manual | Real 4MB MP3: 201 `{trackId,title,status}` in ~1.2 s, with `Access-Control-Allow-Origin`; storage +1 file, DB +1 row |
| 2 | Upload a valid WAV | PASS | curl + browser | Real 10.5MB WAV: 201 in 0.3 s via curl. Through the UI: `POST /api/v1/tracks` (10,544,742 byte body) → 201, then `GET` of the track → 200, and the track is shown |
| 3 | File name with `../` and Vietnamese diacritics | PASS | curl | `filename=../../Thầy Năm.mp3` → 201, stored as `<uuid>.mp3` |
| 4 | Upload a file of the wrong format | PASS | curl + manual | Backend: `application/octet-stream` → 415, storage unchanged. UI: a `.pdf` is blocked with "Only MP3 and WAV files are supported" |
| 5 | Upload a file over 50MB | PASS (backend) | curl | 51 MiB → 413 **with** `Access-Control-Allow-Origin`, storage unchanged. The client-side guard is only covered by a unit test |
| 6 | Get an existing track id | PASS | curl + browser | All 6 fields (`mimeType` is `audio/mpeg` / `audio/wav`, `durationSeconds` is `null`) |
| 7 | Get a non-existent / malformed track id | PASS (backend) | curl | 404 / 400 (and `stream` of an unknown id → 404), all with CORS headers. UI messages only covered by widget tests |
| 8 | Play from the start | PASS | browser + curl | `stream` requests: `Range: bytes=0-` → 206 `Content-Range: bytes 0-10544133/10544134` `audio/wav` (and the same for `audio/mpeg`); the audio element advanced (2.6 s after 3.5 s). A full download is **byte-identical** to the original for both files |
| 9 | Seek to the middle | PASS | browser + curl | Clicking the slider at 50% sent a new request `Range: bytes=5242880-` → 206 `Content-Range: bytes 5242880-10544133/10544134`; playback resumed at 31.17 s of 59.77 s. `Range` slices from the middle of both files are byte-identical to the originals |
| 10 | Seek to the end / back to the start | PASS | browser + curl | Seeking to the very end sent `Range: bytes=10485760-` → 206; the track then finished and the player rewound to 0:00 and paused (Play shows again). Seeking back to the start used the already buffered data (no new request). Backend: `bytes=N-1000`, `bytes=-500`, `bytes=0-0` → 206; `bytes=<size>-` → 416 |
| 11 | Reload the page and re-enter the id | PASS | browser | A fresh page, id typed in "Load by id": track `GET` 200, then `stream` 206, playing |
| 12 | Restart backend + Postgres (not `down -v`) | PASS | curl + browser | `docker restart lasono-postgres` and a backend restart: all 16 DB rows were kept; the MP3 and WAV uploaded before the restart were loaded and played from the browser |
| 13 | Upload with a blank title | PASS | curl + manual | Backend: 400 `Track title must not be blank`, storage unchanged. UI: "Enter a title" |
| 14 | Upload a `.txt` renamed to `.mp3` | PASS (limitation) | curl | Sent as `audio/mpeg`, the backend accepts it (201) because it only trusts the MIME type |
| 15 | Unknown origin | PASS | curl | `Origin: http://evil.example` → 403, no `Access-Control-Allow-Origin`; a preflight from the allowed origin → 200 |

Extra checks: an empty file → 400 `File size must be greater than 0` with storage unchanged; a second upload on the same page works; the backend log during repeated seeking contains only the expected `MaxUploadSizeExceededException` and malformed-UUID warnings, with no stack trace caused by cancelled requests.

## Bugs found during testing (fixed)

| Symptom | Cause | Fix |
|---------|-------|-----|
| After a track played to the end, seeking made no sound until Pause then Play | `just_audio` keeps `playing = true` after the end, so the button still showed Pause and seeking did not restart playback | On completion: pause, rewind to 0:00 and show the Play button again. Browser check: after the end `paused = true`, `currentTime = 0`; a seek is silent until Play, and Play then advances |
| After an upload, the slider kept showing the previous track's duration until Play was pressed | `just_audio`'s `duration`/`position` streams replay their latest value to new subscribers | Subscribe only after the new track has loaded. Browser check: after playing the WAV, uploading the MP3 shows `0:00 / 0:00` with a disabled slider; after Play the duration is 250.29 s |
| Upload of a 4MB/10MB file sat at `(pending)` forever and the form stayed disabled | The backend that was running did not have the upload fixes: Spring's default 1MB limit rejected the file with a 413 that had no CORS header, so the browser never saw the response. Reproduced with curl against that backend | Run a backend that includes the CORS filter and the 50MB limit. The client now also gives up after 5 minutes with "Upload timed out" so the form recovers |

## Open issue

- The user reported "Upload timed out" for the 10MB WAV after the client timeout was added. It **could not be reproduced** with the current backend: through the same UI in headless Chromium the 10.5MB WAV uploaded in about 4 seconds. The most likely cause is that the backend running at that moment was still a build without the upload fixes (it must return `Access-Control-Allow-Origin` on a 413 or accept the file). Please re-test in Chrome with a freshly restarted backend; if it still happens, capture the response of the `tracks` request in DevTools.
- In headless automation the first click on "Choose file" after typing in a text field was sometimes ignored and a second click opened the dialog. It was not observed in the manual tests.

## Known limitations

- The backend only trusts the MIME type sent by the client and does not inspect the file content (magic bytes).
- Flutter web reads the whole file into tab RAM; only the 50MB limit is checked.
- `JustAudioPlayerService` (the `just_audio` wrapper) has no automated test; it was verified through the browser run above.
- The dev data now contains test tracks created by these runs (titles starting with "E2E", "BROWSER", "G", "dbg", "traversal", "fake", "TEST WAV 10Mb").

## Still to do

- Re-run the 10MB WAV upload manually in Chrome against a freshly started backend (see the open issue).
- Seek on a WAV/MP3 in a manual session once more to confirm the `Range` requests in the Network tab (done here in headless Chromium).
