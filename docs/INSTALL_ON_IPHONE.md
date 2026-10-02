# Putting Morsel on your iPhone without a Mac

Two routes. Start with the free one; move to TestFlight when the weekly re-sign gets old.

## Route A: free Apple ID + Sideloadly (Windows)

What you get: the real app on your phone, camera and barcode scanner working.
Limits of a free Apple ID: the app expires after 7 days and must be re-signed
(plug the phone in, click Start again), at most 3 sideloaded apps at a time,
and the phone must be plugged into the PC the first time.

1. On the PC, install iTunes from apple.com (not the Microsoft Store build) so the
   Apple USB drivers are present, then install Sideloadly from https://sideloadly.io.
2. Download `Morsel-unsigned.ipa` from the GitHub release
   https://github.com/ashtonkirkman/morsel/releases/tag/latest
   (CI refreshes it on every push to main).
3. Plug the iPhone in, tap Trust, open Sideloadly, drag the IPA in, enter your
   Apple ID, click Start. Sideloadly asks for your Apple ID password and any 2FA
   code; it signs the IPA with a free development certificate and installs it.
4. On the phone: Settings > Privacy & Security > Developer Mode > on (reboot), then
   Settings > General > VPN & Device Management > trust your Apple ID.
5. Open Morsel. For the photo feature, go to Settings > Claude and either paste an
   Anthropic API key (direct mode) or point it at your deployed proxy.

Re-sign every 7 days by repeating step 3. Sideloadly can do this over Wi-Fi after
the first USB install if you enable it in its settings.

## Route B: Apple Developer Program ($99/yr) + TestFlight, driven entirely by CI

What you get: installs over the air from the TestFlight app, builds last 90 days,
no cable, no weekly ritual, and later a real App Store release. Still no Mac: the
GitHub Actions macOS runner does all signing and uploading.

1. Enrol at https://developer.apple.com/programs/enroll (needs the Apple Developer
   app on the iPhone for identity verification). Approval can take a day or two.
2. In App Store Connect create an API key (Users and Access > Integrations > App
   Store Connect API, role App Manager) and note Key ID, Issuer ID, and the .p8.
3. Create an empty private GitHub repo `morsel-certificates` for fastlane match.
4. Add repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`
   (base64 of the .p8), `MATCH_PASSWORD`, `MATCH_GIT_TOKEN` (PAT with repo scope),
   and `APPLE_TEAM_ID`.
5. Run the `TestFlight` workflow by hand once (workflow_dispatch). The first run
   creates the certificate and profile through match, builds, and uploads.
6. Install TestFlight on the phone and accept the invite sent to your Apple ID.

The fastlane lanes already exist in `fastlane/Fastfile`; wiring the workflow and
secrets is the remaining piece once you have a Team ID.
