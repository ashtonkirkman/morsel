# Free Track account API

A Cloudflare Worker with a D1 (SQLite) database that gives the Free Track iOS app user accounts
and cross-device sync. No framework, no dependencies at runtime: plain `fetch` handler, WebCrypto,
D1 prepared statements.

- **Sign in with Apple** (native): the app posts Apple's identity token; the Worker verifies it
  against Apple's JWKS (`iss`, `aud` = bundle id, `exp`, RS256 signature).
- **Google / Facebook**: OAuth 2.0 authorization-code flow with PKCE through
  `ASWebAuthenticationSession`. Client secrets live only here. Tokens never travel in a URL.
- **Sessions**: 1-hour HS256 access JWT + 30-day rotating refresh token (hash stored in D1).
- **Sync**: a generic per-user `documents` table. Any Codable collection on the phone
  (`log-entries`, `favorites`, `settings`, `body-scans`, ...) is a bag of
  `{ id, json, updatedAt, deleted }` documents merged last-writer-wins.

## Endpoints

| Method | Path | Auth | Body / query | Returns |
|---|---|---|---|---|
| `POST` | `/v1/auth/apple` | – | `{ identityToken, authorizationCode?, fullName?: { givenName?, familyName? } }` | session bundle |
| `GET` | `/v1/auth/google/start` | – | `?code_challenge=<S256>&state=<app state>` | 302 to Google |
| `GET` | `/v1/auth/google/callback` | – | (Google redirects here) | 302 to `freetrack://auth/callback?code=…&state=…` |
| `GET` | `/v1/auth/facebook/start` / `/callback` | – | same as Google | same |
| `POST` | `/v1/auth/exchange` | – | `{ code, codeVerifier }` | session bundle |
| `POST` | `/v1/auth/refresh` | – | `{ refreshToken }` | session bundle (refresh token rotated) |
| `POST` | `/v1/auth/logout` | – | `{ refreshToken }` (or Bearer) | 204 |
| `GET` | `/v1/me` | Bearer | | `{ id, displayName, email, avatarUrl, createdAt, providers }` |
| `DELETE` | `/v1/me` | Bearer | | 204 — user, identities, sessions and every document are deleted |
| `GET` | `/v1/sync/{collection}` | Bearer | `?since=<unix ms>` | `{ collection, documents: [{ id, json, updatedAt, deleted }], serverTime }` |
| `PUT` | `/v1/sync/{collection}` | Bearer | `{ documents: [{ id, json, updatedAt, deleted? }] }` (≤ 500, ≤ 64 KB each) | `{ accepted, serverTime }` |
| `GET` | `/healthz` | – | | `{ ok: true }` |

Session bundle: `{ accessToken, accessExpiresAt, refreshToken, refreshExpiresAt, user }`
(timestamps are Unix milliseconds). Errors follow the proxy's shape:
`{ "type": "error", "error": { "type": "...", "message": "..." } }`.

### Sync rules

- `updatedAt` is the **client** clock and decides conflicts: a write is accepted only when its
  `updatedAt` is strictly newer than the stored row (`ON CONFLICT ... WHERE excluded.updated_at >
  documents.updated_at`). A tombstone (`deleted: true`) is just another write, so an edit made later
  on another device wins over it and the document comes back.
- `since` / `serverTime` are the **server** clock (`synced_at`), so a document saved with a stale
  phone clock is still delivered to the other devices. Clients store `serverTime` from each response
  and pass it as the next `since`. Re-receiving a document is harmless (same merge rule).
- Collection names: `^[a-z][a-z0-9_-]{0,39}$`. Document ids: 1–128 chars, usually a UUID.
- The server never looks inside `json`; it is an opaque blob the app encodes with `JSONEncoder`.

### Session model

| Token | Format | Lifetime | Storage |
|---|---|---|---|
| Access | HS256 JWT `{ sub: userId, sid: sessionId, typ: "access", iat, exp }` signed with `SESSION_SECRET` | 1 hour | Keychain on the phone, nowhere on the server |
| Refresh | 32 random bytes, base64url | 30 days, rotated on every `/refresh` | SHA-256 in `sessions.refresh_token_hash` |

Every authenticated request verifies the JWT **and** loads the `sessions` row, so logout and
account deletion take effect immediately rather than at the end of the access window.

### OAuth state and one-time codes

The `state` sent to Google/Facebook is a signed 10-minute JWT carrying the PKCE challenge and the
app's own `state`, so the Worker stores nothing until the provider calls back. The callback stores a
one-time code (hashed) bound to the challenge in `auth_codes` (5 minutes) and redirects to the app;
`/v1/auth/exchange` deletes the row atomically (`DELETE ... RETURNING`), checks
`SHA256(codeVerifier) == challenge`, and only then issues tokens.

### Rate limiting

Auth endpoints use the optional `RATE_LIMITER` binding (20 requests / 60 s per client IP) when it
is configured; uncomment the `[[ratelimits]]` block in `wrangler.toml`. Sync endpoints need a valid
session and are bounded by the per-request document limits, so they are not separately limited.

## Deploy

```bash
cd server/account-api
npm ci
npx wrangler login
npx wrangler d1 create freetrack                 # paste the printed database_id into wrangler.toml
npx wrangler d1 migrations apply freetrack --remote
npx wrangler secret put SESSION_SECRET          # e.g. openssl rand -base64 48
npx wrangler secret put GOOGLE_CLIENT_ID
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put FACEBOOK_APP_ID
npx wrangler secret put FACEBOOK_APP_SECRET
npx wrangler secret put APPLE_BUNDLE_ID         # optional, defaults to com.ashtonkirkman.morsel
npx wrangler deploy                             # prints https://freetrack-account-api.<subdomain>.workers.dev
```

Then paste that URL into Free Track → **Settings → Account → Server URL** (or set
`AccountConfig.defaultBaseURL` in `FreeTrack/Core/Account/AccountConfig.swift` before building so
users never have to).

### Google OAuth client

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → create a project →
   **OAuth consent screen**: External, app name "Free Track", add the `email`, `profile`, `openid`
   scopes. Publish it (testing mode only allows listed test users).
2. **Credentials → Create credentials → OAuth client ID → Web application** (yes, web: the
   exchange happens on the Worker, not on the phone).
3. Authorized redirect URI: `https://freetrack-account-api.<subdomain>.workers.dev/v1/auth/google/callback`
   (add `http://127.0.0.1:8787/v1/auth/google/callback` for `wrangler dev`).
4. Copy the client ID and secret into the two `wrangler secret put` commands above.

### Facebook app

1. [Meta for Developers](https://developers.facebook.com/apps/) → **Create app** → type
   "Consumer" → add the **Facebook Login** product.
2. Facebook Login → **Settings** → *Valid OAuth Redirect URIs*: the same callback URL with
   `/facebook/callback`. Leave "Login with the JavaScript SDK" off.
3. App settings → Basic: copy **App ID** and **App Secret** into the secrets. Add a Privacy Policy
   URL and switch the app to **Live** mode, otherwise only app admins/testers can sign in.
4. The `email` permission is granted automatically for Consumer apps; no App Review needed for
   `public_profile` + `email`.

### Sign in with Apple

1. [developer.apple.com → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   → App ID `com.ashtonkirkman.morsel` → tick **Sign in with Apple** → Save.
2. Regenerate the provisioning profile (Xcode does this with automatic signing; `fastlane match`
   needs `match --force`).
3. Nothing to configure on the Worker beyond `APPLE_BUNDLE_ID` (defaults to the bundle id). The
   identity token's signature is checked against `https://appleid.apple.com/auth/keys`.

**Token revocation (not implemented).** Apple's guidelines ask apps that offer account deletion to
also revoke the Sign in with Apple token via `https://appleid.apple.com/auth/revoke`. That call
needs a client secret signed with a Sign in with Apple private key (`.p8`). Add it to `DELETE /v1/me`
once the key exists; the app already sends `authorizationCode` on each sign-in.

## Local development

```bash
cp .dev.vars.example .dev.vars        # then fill in the values (git-ignored)
npx wrangler d1 migrations apply freetrack --local
npx wrangler dev                      # http://127.0.0.1:8787 against a local SQLite D1
curl -s http://127.0.0.1:8787/healthz
```

`.dev.vars` holds the same names as the secrets above. Point the app at `http://<your-lan-ip>:8787`
from a phone on the same Wi-Fi (the app accepts `http` URLs for development). The Google/Facebook
redirect URIs must then include the LAN URL as well.

## Development

```bash
npm test                # vitest: JWT, PKCE, sync merge rules, Apple token verification (local RSA key)
npx tsc --noEmit        # typecheck
```

`make api` at the repo root runs both. CI job `account-api` in `.github/workflows/ios.yml` does the same.
