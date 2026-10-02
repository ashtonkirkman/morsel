# Morsel

Calorie logging with the work taken out. Snap a photo, scan a barcode, or type a word; Morsel does the
rest and shows you one number and one ring.

> **Pre-release: not yet built on a Mac.** The owner is developing on Windows/WSL with no Mac and no
> Apple Developer account yet. GitHub Actions (`macos-15` runner) is the verification path: every push
> to `main` generates the Xcode project and runs the unit tests on an iPhone simulator. Nothing here has
> run on a physical device.


## Screenshots

Every push to `main` boots an iOS Simulator on GitHub Actions, walks the app in a seeded demo mode
(`--ui-testing`), and publishes the PNGs to the [`screenshots`](https://github.com/ashtonkirkman/morsel/tree/screenshots)
branch, so the images below are always from the latest build. No Mac involved.

| Today | Add menu | Photo | History |
|---|---|---|---|
| ![Today](https://github.com/ashtonkirkman/morsel/blob/screenshots/02-today.png?raw=true) | ![Add](https://github.com/ashtonkirkman/morsel/blob/screenshots/03-add-menu.png?raw=true) | ![Snap](https://github.com/ashtonkirkman/morsel/blob/screenshots/04-snap.png?raw=true) | ![History](https://github.com/ashtonkirkman/morsel/blob/screenshots/08-history.png?raw=true) |

| Search | Quick add | Settings | Dark mode |
|---|---|---|---|
| ![Search](https://github.com/ashtonkirkman/morsel/blob/screenshots/06-search.png?raw=true) | ![Quick add](https://github.com/ashtonkirkman/morsel/blob/screenshots/07-quick-add.png?raw=true) | ![Settings](https://github.com/ashtonkirkman/morsel/blob/screenshots/09-settings.png?raw=true) | ![Dark](https://github.com/ashtonkirkman/morsel/blob/screenshots/10-today-dark.png?raw=true) |

Locally on a Mac: `make screenshots` writes the same set to `./screenshots/`.

## Features

- **Photo to calories.** Take or pick a meal photo; Claude returns the items, portions, calories and
  macros as structured JSON, with a confidence badge and, when it is unsure, one clarifying question.
  One tap to log.
- **Barcode scanning** against the [Open Food Facts](https://world.openfoodfacts.org) database, with a
  serving editor.
- **Search, favorites and recents** so repeat meals are two taps.
- **Quick add** for "just 300 kcal".
- **Goals from your body stats** using Mifflin-St Jeor (calories, protein, carbs, fat), editable any
  time.
- **History** with day/week/month Swift Charts and **CSV export**.
- **Undo toast** instead of confirmation dialogs; swipe to delete.
- **Dark mode**, Dynamic Type, VoiceOver labels. One accent colour, no clutter.
- **Private by design.** Everything is stored on the phone. Only the photo (plus optional hint text)
  and barcode/search text ever leave the device. See [docs/AI_AND_DATA.md](docs/AI_AND_DATA.md).

## Quick start

| Situation | Do this |
|---|---|
| Mac with Xcode 16 | `brew install xcodegen && xcodegen generate && open Morsel.xcodeproj`, run on a simulator (no signing needed) |
| No Mac | Push a branch, open a PR to `main`, read the **iOS** workflow result; download `TestResults.xcresult` from a failed run |
| Paid Apple Developer account | Set `DEVELOPMENT_TEAM` in `project.yml`, then TestFlight via Xcode Organizer or `fastlane beta` |

Details for all three, including running on your own iPhone with a free Apple ID for 7 days at a time:
**[docs/BUILD.md](docs/BUILD.md)**.

The photo feature needs the Claude proxy (a Cloudflare Worker that holds the Anthropic API key):
**[server/claude-proxy/README.md](server/claude-proxy/README.md)**. Deploy it, paste its URL into
Settings > AI. A "Direct" mode with a key on the device exists for personal use.

## Documentation

| Doc | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module layout, the contract every feature view honours, Claude API request shape |
| [docs/BUILD.md](docs/BUILD.md) | Building with / without a Mac, device installs, TestFlight |
| [docs/DESIGN.md](docs/DESIGN.md) | Colour/type/spacing tokens, components, interaction principles, screen map |
| [docs/AI_AND_DATA.md](docs/AI_AND_DATA.md) | What leaves the device, retention, running the proxy, cost per photo |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | App Store readiness: privacy labels, permission strings, AI disclosure, screenshots, tagging |
| [fastlane/README.md](fastlane/README.md) | `test` and `beta` lanes, prepared for when the account exists |

## Tech stack

- Swift 5.9 language mode, SwiftUI, iOS 17+, iPhone only
- SwiftData for the log; UserDefaults for goals/prefs; Keychain for the optional API key
- AVFoundation / VisionKit for camera and barcodes, Swift Charts for history
- Anthropic Messages API (`claude-opus-5`, structured outputs) through a Cloudflare Worker proxy
- Open Food Facts public API
- XcodeGen project spec, **no third-party Swift packages**
- CI: GitHub Actions (`macos-15`, Xcode 16), SwiftLint (advisory), TypeScript typecheck for the proxy

## Repository layout

```
project.yml              XcodeGen spec (the .xcodeproj is generated, never committed)
Morsel/
  App/                   MorselApp, AppServices (DI), RootView (tabs, + button, toast)
  Core/                  Models (SwiftData), Services (protocols, settings, keychain),
                         Nutrition (Mifflin-St Jeor), Persistence (container, queries, PhotoStore)
  DesignSystem/          Theme tokens + the component set
  Features/              Today, History, Settings, Onboarding, Add, Snap, Scan, Search
  Resources/             Assets.xcassets (icon, accent), PrivacyInfo.xcprivacy
MorselTests/             XCTest unit tests (pure logic)
server/claude-proxy/     Cloudflare Worker holding the Anthropic key
docs/                    Build, design, data and release docs
scripts/                 make_icon.py (app icon), pick_simulator.py (CI helper)
fastlane/                test / beta lanes (need a Mac + developer account)
.github/workflows/       ios.yml
Makefile                 generate / build / test / icon / lint / proxy
```

## Development

```bash
make generate   # xcodegen
make test       # simulator build + MorselTests, same flags as CI (Mac only)
make icon       # regenerate the app icon (python3, Pillow optional)
make lint       # swiftlint, native or via docker
make proxy      # typecheck server/claude-proxy
```

Contribution rules (module boundaries, exact view signatures, API conventions) are in
[ARCHITECTURE.md](ARCHITECTURE.md).

## License

[MIT](LICENSE), (c) 2026 Ashton Kirkman. Nutrition data from Open Food Facts is
[ODbL](https://opendatacommons.org/licenses/odbl/1-0/).
