# fastlane

| Lane | Runs where | What it does |
|---|---|---|
| `fastlane test` | any Mac, free Apple ID | `xcodegen generate`, then `scan` runs `MorselTests` on the newest iPhone simulator |
| `fastlane beta` | `.github/workflows/testflight.yml` (macos-15), or a Mac with the same env vars | `match` (git storage) fetches/creates the Apple Distribution cert + App Store profile, archives Release, uploads to TestFlight |

Setup, secrets and the first-run walkthrough live in `docs/INSTALL_ON_IPHONE.md` (Route B).

Env the `beta` lane reads: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`
(base64 .p8; set `ASC_KEY_CONTENT_BASE64=false` for raw PEM), `MATCH_PASSWORD`, `MATCH_GIT_URL`,
`MATCH_GIT_BASIC_AUTHORIZATION` (base64 `user:PAT`), optional `BUILD_NUMBER`, `TESTFLIGHT_CHANGELOG`,
`MATCH_READONLY=true` to forbid creating new certificates.

No Gemfile is checked in: the GitHub macOS runner ships fastlane preinstalled. On a Mac,
`brew install fastlane xcodegen` is enough.
