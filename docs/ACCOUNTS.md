# Accounts and sync

Free Track stays local-first: everything works without an account. Signing in (Apple, Google or
Facebook) adds a server copy of your data so a second device, or a reinstall, gets your log back.
The server is a small Cloudflare Worker + D1 database you deploy yourself:
[`../server/account-api/README.md`](../server/account-api/README.md).

## iOS pieces

```
FreeTrack/Core/Account/
  AccountConfig.swift        default server URL (TODO placeholder), URL scheme, bundle id
  AccountModels.swift        AuthProvider, AccountUser, SessionBundle, SyncDocument, AccountError, JWTClaims
  AccountAPIClient.swift     AccountAPI protocol, URLSession client, StubAccountAPI (UI tests), SyncCodec
  PKCE.swift                 RFC 7636 verifier/challenge (CryptoKit SHA-256 + base64url)
  AppleSignInCoordinator     ASAuthorizationController wrapped in one async call
  WebOAuthFlow.swift         ASWebAuthenticationSession + WebAuthPresenter + callback parsing
  AccountService.swift       @Observable @MainActor: state (.signedOut / .signedIn), signIn / signOut /
                             deleteAccount / refreshIfNeeded / validAccessToken
  SyncEngine.swift           SyncCollection protocol, ModelSyncCollection<M>, SyncMerge rules, SyncEngine
  SyncCollections.swift      LogEntryDTO, FavoriteFoodDTO, ProfileDocument, SettingsSyncCollection, registerAll
FreeTrack/Core/Models/SyncTombstone.swift   @Model recording local deletions
FreeTrack/Features/Account/
  SignInButtonsView.swift    Apple (SignInWithAppleButton) + Google + Facebook buttons, "why" line
  AccountSettingsSection     Settings > Account (signed-out: buttons + server URL; signed-in: identity, last synced, actions)
  AccountPage.swift          onboarding page 2 (skippable)
```

`AppServices` owns one `AccountService` and one `SyncEngine`; views reach them through
`@Environment(AppServices.self)`. In `--ui-testing` launches `StubAccountAPI` is injected so
screenshots never touch the network.

## Sign-in flows

| Provider | On the phone | On the Worker |
|---|---|---|
| Apple | `SignInWithAppleButton` / `ASAuthorizationAppleIDProvider` returns an identity token (+ name on first sign-in) | `POST /v1/auth/apple` verifies the token against Apple's JWKS (`aud` = `com.ashtonkirkman.morsel`) |
| Google, Facebook | `PKCE.generate()`, open `/v1/auth/{provider}/start?code_challenge&state` in `ASWebAuthenticationSession(callbackURLScheme: "freetrack")`, receive `freetrack://auth/callback?code&state`, `POST /v1/auth/exchange { code, codeVerifier }` | Redirects to the provider, exchanges the provider code with the client secret, upserts the user, issues a one-time code bound to the PKCE challenge |

No provider SDKs are bundled. The `freetrack` URL scheme is declared in `project.yml`
(`CFBundleURLTypes`); `ASWebAuthenticationSession` consumes the callback, so the app does not need
`onOpenURL`.

## Session

- Access token: 1-hour HS256 JWT, Keychain key `accessToken`. `AccountService.validAccessToken()`
  refreshes it when under a minute of life remains; `refreshIfNeeded()` (on foreground) when under
  five minutes.
- Refresh token: 30 days, rotated on each refresh, Keychain key `refreshToken`. A rejected refresh
  signs the user out locally.
- The cached `AccountUser` lives in `AppSettings.accountUserData` so Settings is right at launch.

## Data model on the server

One generic table, `documents(user_id, collection, doc_id, json, updated_at, synced_at, deleted)`.
The app never sends photos; `LogEntryDTO` leaves `photoFilename` out.

| Collection | Document id | Payload |
|---|---|---|
| `log-entries` | `LogEntry.id` | `LogEntryDTO` (flat nutrition fields, meal type, source, notes, confidence) |
| `favorites` | `FavoriteFood.id` | `FavoriteFoodDTO` |
| `settings` | `profile` | `ProfileDocument`: goals, unit system and the `UserProfile` blob (encoded as-is with `JSONEncoder`, decoded leniently) |
| `body-scans` | `BodyScan.id` | `BodyScanDTO` — register with one line, see below |

## Sync rules

1. **Last writer wins** on `updatedAt` (client clock, ms). Ties keep the local copy. Both the app
   (`SyncMerge.remoteWins`) and the SQL upsert on the Worker apply the same rule.
2. **Tombstones are writes.** Deleting locally inserts a `SyncTombstone`; the engine pushes it as
   `{ deleted: true, updatedAt: deletedAt }`. An edit with a later `updatedAt` on another device
   wins over the tombstone and the entry comes back.
3. **Silent edits are caught.** Each run stores a fingerprint of every local document (content
   with `updatedAt` masked). If the content changed but `updatedAt` did not, the engine bumps
   `updatedAt` and pushes. Likewise a document that vanished without a tombstone gets one. So
   feature code does not have to call `context.touch(_:)` / `context.deleteSynced(_:)`, although
   doing so makes the change go out one cycle sooner.
4. **Cursors are server time.** Pulls send `since=<serverTime of the last pull>` per collection
   (`AppSettings.syncCursor(for:)`), so a document saved with a wrong phone clock is still delivered.
5. **Triggers:** sign-in, app foreground, and any `ModelContext.didSave` (debounced three seconds).
   Sync never blocks the UI; errors only show as the "Last synced" line in Settings > Account.
6. **Sign-out keeps local data** and forgets the cursors; signing in to a different account pushes
   everything local as new documents and merges whatever that account already has.
7. **Delete account** (`DELETE /v1/me`) removes the user and every document server-side; the phone
   keeps its copy.

## Adding a collection

For a SwiftData model (the `BodyScan` case):

```swift
extension BodyScan: SyncableModel {           // DTO = BodyScanDTO (id, createdAt, updatedAt, ...)
    var syncID: UUID { id }
    func makeDTO() -> BodyScanDTO { ... }
    func apply(_ dto: BodyScanDTO) { ... }
    convenience init(syncDTO dto: BodyScanDTO) { ... }
}
// in SyncCollections.registerAll:
engine.register(ModelSyncCollection<BodyScan>(name: "body-scans"))
```

`BodyScanDTO` only needs `Codable`, `id: UUID` and `var updatedAt: Date` to satisfy `SyncableDTO`.
The model needs a `var updatedAt: Date = Date.now` property (defaulted so lightweight migration
accepts it) and to be part of `ModelContainer.freeTrackSchema`.

## Pointing the app at your Worker

1. Deploy the Worker (`npx wrangler deploy` in `server/account-api`) and copy the printed URL.
2. Either set `AccountConfig.defaultBaseURL` in `FreeTrack/Core/Account/AccountConfig.swift` and
   rebuild (recommended for TestFlight / App Store), or open **Settings > Account > Server URL** in
   the app and paste it (stored in `AppSettings.accountAPIURLString`). Until one of these is done
   the sign-in buttons explain that accounts are not set up.
3. Local development: `npx wrangler dev` and paste `http://<lan-ip>:8787` (plain `http` is accepted).

## Privacy

What leaves the device, and when, is spelled out in [`AI_AND_DATA.md`](AI_AND_DATA.md). The privacy
manifest declares email, name, user id and health & fitness data as collected, linked to the user,
not used for tracking. App Store review requires an in-app account deletion path when accounts can
be created: Settings > Account > Delete account.
