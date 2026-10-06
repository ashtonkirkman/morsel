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

## Route B: Apple Developer Program + TestFlight, driven entirely by CI

What you get: installs over the air from the TestFlight app, builds last 90 days,
no cable, and later a real App Store release. Still no Mac: the GitHub Actions
macOS runner (`.github/workflows/testflight.yml`, lane `fastlane beta`) signs and
uploads. Signing uses fastlane `match`: one private git repo holds the encrypted
distribution certificate so every run signs with the same identity.

One-time setup, about 20 minutes, all in a browser:

1. **Team ID.** https://developer.apple.com/account > Membership details > Team ID
   (10 characters). Secret `APPLE_TEAM_ID`.
2. **App Store Connect API key.** https://appstoreconnect.apple.com > Users and
   Access > Integrations > App Store Connect API > Team Keys > + . Name "GitHub CI",
   role **Admin** (Admin is needed to create certificates and the app record).
   Download the `.p8` once; Apple never shows it again.
   Secrets: `ASC_KEY_ID` (the Key ID column), `ASC_ISSUER_ID` (top of that page),
   `ASC_KEY_CONTENT` = the contents of the .p8 file. Open it in Notepad, select all,
   paste; the BEGIN/END lines and line breaks are fine (the lane also accepts a
   base64 copy or just the body lines).
3. **Certificates repo.** Create an empty **private** GitHub repo named
   `morsel-certificates` (any name works if you set repository variable
   `MATCH_GIT_URL`). Do not add a README; match wants it empty.
4. **PAT for that repo.** GitHub > Settings > Developer settings > Fine-grained
   tokens > Generate. Repository access: only `morsel-certificates`. Permissions:
   Contents = Read and write. Secret `MATCH_GIT_PAT`.
5. **Passphrase.** Invent one (anything long); match encrypts the certificates with it.
   Secret `MATCH_PASSWORD`. Keep a copy in your password manager.
6. **Add the six secrets** at https://github.com/ashtonkirkman/morsel/settings/secrets/actions:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `MATCH_PASSWORD`, `MATCH_GIT_PAT`.
7. **Run it.** Actions tab > TestFlight > Run workflow. The first run registers the App ID
   and the App Store Connect app record through the API key (if Apple refuses, the log
   prints the two web-UI steps), creates the certificate and profile, archives, and
   uploads. Expect 10-15 minutes.
8. **On the phone.** Install TestFlight from the App Store. In App Store Connect >
   My Apps > Morsel > TestFlight, the build appears after processing (5-30 min); add
   yourself under Internal Testing (your Apple ID must be a user in Users and Access,
   which the account holder always is). Accept the email invite, tap Install.

From then on: Actions > TestFlight > Run workflow (or push a tag `v0.1.1`) ships a new
build; the phone updates through TestFlight. Build numbers come from the workflow run
number, so they never collide.

If you want the Apple ID route A on a paid account: Sideloadly signs for a full year
instead of 7 days, so route A is also a reasonable long-term option for a single phone.
