# ADR 0001: Token strategy for logging in

- **Status:** Accepted
- **Decided:** 2026-10-07 (plan of Phase 4), written down 2026-10-08
- **Where it is built:** `identity` module, `SecurityConfig`, `RefreshCookies`, `RefreshSessionUseCase`; the Flutter `SessionController`

## Context
LaSono has one backend and one browser app on another origin (`localhost:3000` talks to `localhost:8080`). The app must know who is logged in for a long time (days), a stolen credential must do as little harm as possible, and the audio element (`<audio>`) cannot send an `Authorization` header. The project is also a learning project: it should use the real pieces (hashing, tokens, rotation) rather than hide them.

## Decision
1. **Two tokens.**
   - The **access token** is a JWT (HS256, one secret from `LASONO_JWT_SECRET`, at least 32 bytes) that lives 15 minutes. It comes in the JSON body of login and refresh, and the app keeps it **in memory only** and sends it as `Authorization: Bearer`.
   - The **refresh token** is an opaque random value (256 bits) that lives 30 days. It comes **only** in a cookie: `HttpOnly`, `SameSite=Strict`, `Secure` (by default), `Path=/api/v1/auth`. The database stores only its SHA-256 hash.
2. **Rotation and reuse detection.** Every refresh uses up the token and gives a new one in the same *family* (one family per login). If a used token is shown again, the whole family is revoked. There is no grace period.
3. **The app restores the session on start** by calling `POST /auth/refresh` (the cookie goes along), and sends one refresh at a time.
4. **Audio gets a signed address** instead of a header: `GET /tracks/{id}/stream-url` returns a path with `expires` and an HMAC-SHA256 `signature` over `stream:<trackId>:<expires>` (1 hour), given only to someone who may see the track.
5. Spring Security does the work as an OAuth2 resource server (Nimbus decoder); the application code only issues tokens and checks refresh tokens.

## Alternatives considered
| Alternative | Why not |
|-------------|---------|
| Keep the access token in `localStorage` | Any script on the page (an XSS bug, a compromised dependency) can read it and keep it. In memory it is lost on reload, which costs one refresh. |
| One long-lived token (days) and no refresh token | A stolen token would work for days and could not be noticed or revoked. |
| Server-side sessions with a session cookie | Every API call would depend on a session store and on CSRF protection for all `POST`, `PATCH` and `DELETE` routes. With a bearer token the only cookie-carried route is `/auth`, so only that route needs an `Origin` check. |
| A JWT as refresh token | A JWT cannot be revoked or marked as used without a lookup, so rotation and reuse detection would need a table anyway; an opaque token needs no signature and leaks nothing when read. |
| Store the refresh token raw in the database | A copy of the database would be a set of working logins. |
| A grace period for a token that was just used | It removes the "two tabs" logout, but it also lets a thief use a stolen token in that window. Kept out on purpose; the client avoids the race instead. |
| RS256 with a key pair | Useful when other services check tokens. Here one service signs and checks, so a shared secret is simpler. |
| The token in the query string of the stream address | It would be a login in a URL. The signature covers one track and one hour and carries no identity. |

## Consequences
- **An access token cannot be revoked before it expires** (15 minutes at most). Logout and a revoked family stop *new* access tokens, not the one already issued. A token for an account that is deleted answers `401`.
- **The client must send one refresh at a time**, and a second tab can still end the session. This is a known limit (see `docs/phase-4-identity.md`).
- **Cookies bring CORS and site rules.** The API allows credentials from the listed origins; the `SameSite=Strict` and `Secure` cookie is not sent when the app and the API are different sites or when the API is on plain `http://<IP>`. The README workaround for a stuck `wslrelay` therefore logs in but loses the session on reload.
- **A public route is not safe from a bad token:** Spring checks any `Authorization` header it sees, even on `permitAll` routes. The auth routes ignore the header, and the app refreshes and repeats on `401`.
- **The signature can appear in access logs** (it is in the query string) and anyone who holds the address can play that track until it expires.
- The refresh token hash lookup takes a row lock (`SELECT … FOR UPDATE`) and the use case does not roll back on an invalid token (`noRollbackFor`), because the revoke must be kept (see `docs/learning-log.md`).
- **Not done yet:** login rate limiting, a cleanup of expired refresh tokens, and a log or alarm when a family is revoked for reuse (it is silent today).
