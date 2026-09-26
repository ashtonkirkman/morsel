# Building Morsel

Morsel is a SwiftUI app for iOS 17+. The Xcode project is **generated** from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); there is no checked-in `.xcodeproj`. There are no
third-party Swift packages, so a build needs nothing but Xcode.

Pick the path that matches what you have.

| You have | Path |
|---|---|
| A Mac with Xcode 16 | [A. Mac with Xcode](#a-mac-with-xcode) |
| No Mac (Windows / Linux / WSL) | [B. No Mac: GitHub Actions is the build machine](#b-no-mac-github-actions-is-the-build-machine) |
| A Mac **and** a paid Apple Developer account | [C. Apple Developer Program: TestFlight and the App Store](#c-apple-developer-program-testflight-and-the-app-store) |

---

## A. Mac with Xcode

```bash
brew install xcodegen
git clone <repo> morsel && cd morsel
xcodegen generate            # or: make generate
open Morsel.xcodeproj
```

Then in Xcode: select the `Morsel` scheme, pick an iPhone simulator, press Run. **The Simulator needs
no signing and no Apple account at all.**

Command line equivalents (identical flags to CI):

```bash
make build        # Debug build on the newest iPhone simulator
make test         # build + MorselTests, results in TestResults.xcresult
```

### Running on a physical iPhone with a free Apple ID

1. Xcode > Settings > Accounts > add your Apple ID. Xcode creates a **Personal Team**.
2. Select the `Morsel` target > Signing & Capabilities > Team: your Personal Team. Xcode may ask you to
   change the bundle ID if `com.ashtonkirkman.morsel` is taken on another Personal Team; use
   `com.<you>.morsel` locally and do not commit it (or set `PRODUCT_BUNDLE_IDENTIFIER` via an
   `xcodegen`-ignored `.xcconfig`).
3. Plug in the phone, trust the computer, enable Developer Mode on the phone (Settings > Privacy &
   Security > Developer Mode), and Run.
4. On the phone: Settings > General > VPN & Device Management > trust your developer certificate.

Limits of a Personal Team: the app **expires after 7 days** (re-run from Xcode to renew), at most 3 apps
installed this way, no TestFlight, no push. Fine for daily personal use while the paid account is pending.

Because `project.yml` regenerates the project, **do not edit build settings inside Xcode**; change
`project.yml` and re-run `xcodegen generate`.

---

## B. No Mac: GitHub Actions is the build machine

This is the situation today. Every push and pull request to `main` runs
[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) on a `macos-15` runner:

1. `brew install xcodegen` and `xcodegen generate`
2. picks the newest available iPhone simulator (`scripts/pick_simulator.py`)
3. `xcodebuild ... build test` with signing disabled, output through `xcpretty`
4. on failure, uploads `TestResults.xcresult` as a workflow artifact (download it from the run's
   Summary page; it opens in Xcode on any Mac, and `xcrun xcresulttool get --format json` reads it).

That job is **the only compile check we have**. Work in small PRs so a red build points at one change.
Two side jobs run on Ubuntu: SwiftLint (advisory, never fails the build) and a TypeScript typecheck of
`server/claude-proxy` (skipped until that folder has a `package.json`).

Tips for iterating without a Mac:

- Swift syntax can be checked locally with the Linux toolchain (`swift.org` tarball or the
  `swift:6.0` Docker image), but only for pure-Swift files that import `Foundation`; anything with
  `SwiftUI`/`UIKit`/`SwiftData` will not resolve. It still catches typos before a 15-minute CI round trip.
- Re-run a failed job with debug logging from the Actions UI ("Re-run jobs" > "Enable debug logging").
- The `workflow_dispatch` trigger lets you run CI on any branch from the Actions tab.

### Getting the app onto a phone with no Mac of your own

Installing on a device always requires Xcode, so you need temporary access to a Mac:

- **Rent one by the hour/month:** [MacStadium](https://www.macstadium.com), [Scaleway Apple silicon
  M-series](https://www.scaleway.com/en/hello-m1/), [MacinCloud](https://www.macincloud.com). Connect via
  Screen Sharing / VNC, follow path A. USB device pass-through is not possible remotely, so on a rented Mac
  build for the Simulator, or use it with a paid account for TestFlight (path C).
- **Borrow a friend's Mac for an hour:** path A with a free Apple ID; the 7-day expiry applies.
- **CI cannot install to a phone** (no device attached, no signing identity). Once the paid account
  exists, CI can ship to TestFlight instead, which is the real answer.

---

## C. Apple Developer Program: TestFlight and the App Store

Requires the $99/year [Apple Developer Program](https://developer.apple.com/programs/enroll/) and a Mac.

1. **Team ID.** After enrolment, copy the 10-character Team ID (developer.apple.com > Membership) into
   `project.yml`:

   ```yaml
   settings:
     base:
       DEVELOPMENT_TEAM: "XXXXXXXXXX"
   ```

   Commit it; it is not a secret. `CODE_SIGN_STYLE: Automatic` is already set.
2. **App ID.** Certificates, Identifiers & Profiles > Identifiers > register `com.ashtonkirkman.morsel`
   (explicit, no extra capabilities needed).
3. **App record.** App Store Connect > My Apps > New App > iOS, name "Morsel", the bundle ID above, SKU
   `morsel`.
4. **First TestFlight build, via Xcode:** `xcodegen generate`, open the project, Product > Archive,
   then Organizer > Distribute App > TestFlight & App Store. Automatic signing creates the
   distribution certificate and profile for you.
5. **Or via fastlane:** see [`fastlane/README.md`](../fastlane/README.md). `fastlane beta` archives with
   `-allowProvisioningUpdates` and uploads with an App Store Connect API key from `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`. No `match`, no certificate repo.
6. **Versioning.** `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build number) live in
   `project.yml`. Every TestFlight upload needs a higher build number; `fastlane beta` bumps it from the
   last TestFlight build automatically.
7. Before submitting for review, walk through [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `xcodegen: command not found` in CI | Homebrew hiccup; re-run the job. |
| `Unable to find a destination matching` | No iPhone runtime on the runner image; check the "Pick newest iPhone simulator" step log. |
| Signing errors on the simulator | Should never happen: CI passes `CODE_SIGNING_ALLOWED=NO`. Locally use `make build`. |
| Xcode complains about `PrivacyInfo.xcprivacy` | It must be in Copy Bundle Resources. XcodeGen 2.40.1+ does this automatically; `brew upgrade xcodegen`. |
| Project looks stale after pulling | `xcodegen generate` again. The `.xcodeproj` is a build artifact. |
