# Phase 4: Identity

## Goal
Tracks get owners. A person can register, log in, upload under their name, keep a track private, edit or delete only their own tracks and have a small public profile. Before this phase the API was open to everyone and every track belonged to nobody.

## What works now
- **Accounts:** `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `GET /users/me`. A login gives a short access token (JWT, 15 minutes) in the body and a long refresh token (30 days) in an `HttpOnly` cookie.
- **Ownership:** every track has an `owner_id`. Uploading needs a login and the owner is the user in the token, never a field of the request.
- **Visibility:** a track is `PUBLIC` or `PRIVATE`. A private track is "not found" (404) for everyone but its owner, in the detail, the stream and every list.
- **Playing a private track:** the audio element cannot send a login header, so `GET /tracks/{id}/stream-url` gives an address with a signature and an expiry (1 hour) that `/stream` accepts.
- **Owner tools:** `PATCH /tracks/{id}` (title, description, visibility; a missing field stays as it is) and `DELETE /tracks/{id}`, for the owner only.
- **Profile:** `GET /users/{id}` gives `{userId, displayName}` (never the email), `PATCH /users/me` changes the display name, `GET /users/{id}/tracks` lists one user's tracks, a page at a time.
- **App:** register and log in screen, the session kept in memory and restored by the cookie on reload, a Private switch on the upload form, Edit and Delete for the owner, a profile page with a rename for its owner.

Delivered as ten stacked pull requests: #32 register and the security base, #33 login and JWT, #35 refresh rotation and logout, #36 owner on tracks, #37 visibility and the signed address, #38 edit and delete, #39 profile API, #40 the app logs in, #41 profile and owner tools in the app, and this one (documentation). #34 (a CI timeout for the ffmpeg install) is independent.

## End-to-end check (2026-10-08)
Real backend (`bootRun` on port 8081, scratch database copied from the dev one, JWT secret from the environment), Flutter web on port 3000, headless Chromium driven by Playwright. The cookie is `Secure` (the default) and the page is served from `http://localhost`.

| # | Scenario | Result |
|---|----------|--------|
| 1 | Open the app with no cookie | `POST /auth/refresh` gives `401`, then the track list is asked for (`200`), and the top bar offers **Log in** |
| 2 | Create an account | `register` `201`, `login` `200`, `users/me` `200`, the list loads again, the top bar shows the name |
| 3 | The cookie after login | `lasono_refresh`, `HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/api/v1/auth` |
| 4 | Reload the page | `refresh` `200`, `users/me` `200`: the name is back without a login |
| 5 | Log out | `logout` `204`, the cookie is gone, the list loads again |
| 6 | Upload a **private** track with a token (cross-origin) | `201` |
| 7 | A stranger (no login) asks the list | The private track is not in it |
| 8 | The owner opens it and presses Play | `stream-url` `200`, then `stream?expires=…&signature=…` `206` |
| 9 | Edit: switch Private off, Save | `PATCH` `200`; the stranger now sees the track |
| 10 | Profile page, rename | `GET /users/{id}` and `/users/{id}/tracks` `200`; `PATCH /users/me` `200`, the title changes |
| 11 | Delete the track from the player | `DELETE` `204`, the profile page loads again and is empty |

Not tried for real: the moment the access token runs out (15 minutes) and the app refreshes and repeats a request (unit tests only), and a signed address that has expired.

Automated tests at the end of the phase: 607 backend tests, 125 `postgresTest`, 232 Flutter tests, 0 failures. `postgresTest` includes end-to-end tests over HTTP on a real PostgreSQL (refresh, upload with an owner, private tracks, edit and delete, the profile page) and tests that run the migrations V4 to V7 on a scratch schema.

## Key design decisions and why
| Decision | Why |
|----------|-----|
| Spring Security as a resource server with Nimbus and HS256 (one shared secret from `LASONO_JWT_SECRET`, at least 32 bytes) | One service signs and checks its own tokens, so a shared secret is enough and there is no key server. The framework does the parsing and the checks. |
| A short access token (15 min) in the response body, kept by the app in memory only | A script on the page cannot read it from storage. Losing it costs one `refresh`. |
| The refresh token is an opaque random value (256 bits), and only its SHA-256 hash is stored | A copy of the database does not give working tokens. No JWT is needed because the server always looks the token up. |
| The refresh token lives in an `HttpOnly`, `SameSite=Strict`, `Secure` cookie with `Path=/api/v1/auth` | A script cannot read it, a foreign site cannot make the browser send it, and it goes to no route but the auth routes. The cross-site `Origin` check needed no new code: the existing CORS filter already answers `403` to a foreign origin on `/api/**`. |
| Rotation with token families: each refresh gives a new token and uses up the old one; showing a used token again revokes the whole family | A stolen token is noticed the first time two people use it. There is no grace period on purpose, so the client must send one refresh at a time. |
| `RefreshSessionUseCase` is `@Transactional(noRollbackFor = InvalidRefreshTokenException.class)` and reads the token row with `SELECT … FOR UPDATE` | The revoke must survive the exception that answers `401`, and two requests with the same token must not both win. |
| Login answers one `401` for every failure and always does one BCrypt comparison | A caller learns neither whether an email exists nor how long a wrong email takes. |
| BCrypt cost 10; a password has 8 characters at least and 72 **bytes** at most | BCrypt only reads the first 72 bytes, so a longer password would silently match a shorter one. |
| Old tracks belong to a "legacy" user that migration V6 creates only if old tracks exist; `owner_id` is `NOT NULL` with no foreign key | The migration works on an empty database and on a full one. No foreign key, because the modules do not know each other's tables (below). |
| The `track` and `identity` modules share nothing but ids; an ArchUnit rule fails the build if one depends on the other | The track module knows an owner only as an id. The profile page asks two modules and the app puts the answers together. |
| A private track is `404` to a non-owner, and always before "not ready" (`409`); editing a visible track that is not yours is `403` | `403` for a private track would say that it exists. A public track is no secret, so `403` is honest there. |
| Visibility is a column with a `CHECK` constraint and no default | A row cannot hold a value the code does not know, and an insert that forgets it fails instead of becoming public by accident. |
| The list filter for private tracks is in the SQL (`visibility = 'PUBLIC' OR owner_id = :viewer`), nobody logged in is the nil UUID | The page, the cursor and the filter are one query, so they always agree. |
| Signed stream address: HMAC-SHA256 over `stream:<trackId>:<expires>`, valid while `now < expires`, key `lasono.stream.signing-secret` (the JWT secret by default), 1 hour | `<audio>` cannot send a header. The signature is bound to one track and one time, and is only given to someone who may see the track. |
| `PATCH` is partial (a missing field stays, an empty description clears it) and runs under a row lock | Two edits of different fields do not undo each other, and an edit cannot meet a delete half way. |
| `DELETE` removes the database rows in one transaction and the files afterwards, best effort; a `PROCESSING` track answers `409` | A file left behind is harmless, a row that points to no file is not. The worker's `save` is an upsert, so deleting a track under it would bring the track back. |
| The profile never carries the email; `/users/me` is matched before `GET /users/*` | The email is private. `*` also matches `me`, so the order of the rules decides which one is public. |
| Flutter: one refresh at a time; on `401` the app refreshes once and repeats the request once | The backend rotates the token, so two refreshes at once would end the session. A second `401` is the answer, so there is no loop. |
| Flutter: the public `GET` routes also repeat on `401`, but a profile is read without a token | The server refuses an expired token even on a public route. A route that needs no login is better off sending none. |
| Flutter: the signed address is asked for when Play is pressed, not when the screen opens | It is always fresh and the screens that only show a track make no extra request. |
| The web client for the auth routes sets `withCredentials` (a `BrowserClient` chosen by a conditional import) | Without it the browser sends no cookie from `localhost:3000` to `localhost:8080`. |

## Pitfalls found
- **The revoke was rolled back by the exception.** A reused refresh token revokes its family and then throws, and a `RuntimeException` rolls the transaction back, so the stolen family stayed alive while the caller saw a `401`. Fix: `noRollbackFor` (see `learning-log.md`).
- **A stale token breaks public routes.** Spring checks any `Authorization` header it sees, so an expired token turns `GET /tracks` into `401` and a login with an old token into `401`. The auth routes now ignore the header, and the app refreshes and repeats (see `learning-log.md`).
- **`/users/*` matches `/users/me`.** With the public rule first, the page with the email was open to everyone. Two tests turn red if the order is swapped.
- **A deleted track came back.** The worker's `save` writes the row again if it is missing, so deleting a `PROCESSING` track was undone a moment later. Fix: refuse it with `409`.
- **BCrypt reads 72 bytes.** A long password (or one with many multi-byte characters) matched any password that shares its first 72 bytes. The limit is now in bytes.
- **A fake that was stricter than the database.** The in-memory user repository refused to save the same user twice, which a real `UPDATE` allows. The fake now replaces by id.
- **A test that was green for the wrong reason.** The check on the visibility constraint passed because the error text mentioned the missing column. A mutation showed it, and the test now looks at the constraint.
- **Editing an applied migration** breaks Flyway's checksum check, so every test turns red. For a mutation check, run with `SPRING_FLYWAY_VALIDATE_ON_MIGRATE=false`.
- **A RED test that hung.** An unbounded wait in a concurrency test waited for ever; every wait in those tests is now bounded.
- **`PESSIMISTIC_WRITE` needs a transaction**; the lock tests wrap the call in a `TransactionTemplate`.
- **`--tests` only filters the last Gradle task** when two tasks are given, so the first one runs everything. Run `test` and `postgresTest` as separate commands.
- **`PopupMenuButton` does not call `onSelected` for a `null` value**, so a menu item with `value: null` did nothing.
- **One end-to-end test failed once** during a mutation run (the owner's signed address) and could not be reproduced in more than five later runs. If it comes back, look at timing first.
- **CI hung on `apt-get install ffmpeg`** for 19 minutes; PR #34 gives that step a 5 minute limit.

## Known limits
- No rate limit on login, so passwords can be guessed as fast as BCrypt allows.
- `register` answers `409` for an email that exists, so anyone can test which emails are registered.
- No grace period for refresh: two tabs that refresh at the same moment make one of them end the session. The app sends one refresh at a time inside a tab, but not across tabs.
- A failed refresh (for example a `401`) leaves the old cookie in the browser until the next login or logout.
- The signature is in the query string of the stream address, so it can show up in an access log. It is valid for one track and one hour.
- A `PROCESSING` track cannot be deleted; the owner has to wait for `READY` or `FAILED`.
- A `Secure` cookie is not accepted over plain `http://<IP>`, so the README's workaround for a stuck `wslrelay` (the app talking to the WSL address) logs the user in but loses the session on reload.
- The track side cannot tell a user that never existed from one with no tracks, so `GET /users/{id}/tracks` answers an empty list for any id. The app reads the profile first and shows "User not found".
