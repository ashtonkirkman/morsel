# fastlane (prepared, not yet runnable)

Nothing in this folder can run today: fastlane needs macOS + Xcode, and the `beta` lane additionally
needs a paid Apple Developer Program membership and an App Store Connect API key. The files are here so
the release process is written down and reviewable before the account exists.

| Lane | Needs | What it does |
|---|---|---|
| `fastlane test` | Mac + Xcode (free Apple ID is fine, simulator needs no signing) | `xcodegen generate`, then `scan` runs `MorselTests` on the newest iPhone simulator |
| `fastlane beta` | Mac + Xcode + **Apple Developer Program** + ASC API key | Bumps the build number, archives Release with automatic signing, uploads to TestFlight |

## One-time setup (after the $99 membership is active)

1. Set `DEVELOPMENT_TEAM` in `project.yml` to the 10-character Team ID (Developer Portal > Membership).
2. Register the App ID `com.ashtonkirkman.morsel` in the Developer Portal and create the app record in
   App Store Connect (same bundle ID, name "Morsel").
3. App Store Connect > Users and Access > Integrations > App Store Connect API > create a key with the
   **App Manager** role. Download the `.p8` once (Apple never shows it again).
4. Export before running the lane (or store them as GitHub Actions secrets for a future release job):

   ```bash
   export ASC_KEY_ID=ABC123DEFG
   export ASC_ISSUER_ID=12345678-aaaa-bbbb-cccc-1234567890ab
   export ASC_KEY_CONTENT="$(cat ~/Downloads/AuthKey_ABC123DEFG.p8)"
   # or: export ASC_KEY_CONTENT="$(base64 -i AuthKey.p8)" ASC_KEY_CONTENT_BASE64=true
   ```

5. On the Mac: `brew install xcodegen && gem install bundler && bundle install` (see Gemfile below), then
   `bundle exec fastlane beta`.

Signing is Xcode automatic signing via `xcodebuild -allowProvisioningUpdates`, authenticated by the API
key. We deliberately do **not** use `match`; there is one developer and no shared certificate repo to keep.

## Gemfile

fastlane is installed per-project. Create `Gemfile` at the repo root on the Mac:

```ruby
source "https://rubygems.org"
gem "fastlane"
gem "xcpretty"
```

then `bundle install`. (It is not checked in yet so the repo does not carry a `Gemfile.lock` generated on
a machine we do not have.)

## Where this plugs into CI

`.github/workflows/ios.yml` currently runs the same simulator build/test as the `test` lane without
fastlane. A `release` job calling `fastlane beta` can be added once the three `ASC_*` values exist as
repository secrets and `DEVELOPMENT_TEAM` is committed.
