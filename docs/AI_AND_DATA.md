# AI and data: what leaves the device

Free Track is a local-first app. Everything you log lives in a SwiftData store on the phone, photos live in
the app's Application Support folder, and goals/preferences live in UserDefaults. Three actions send data
off the device, and only when you start them. A fourth, optional, is signing in to an account, which
syncs your data to a server you (the developer) run; see [Accounts](#accounts-and-sync-optional).

## What is sent, where, and why

| When you... | What leaves the phone | Goes to | Why |
|---|---|---|---|
| Snap or pick a meal photo | The photo, downscaled to at most 1600 px on the long edge and JPEG-compressed (~150-400 KB), plus the optional hint text you type ("two slices", "no dressing") and your answer to the clarifying question | Free Track's AI proxy (a Cloudflare Worker you deploy), which forwards it to the OpenAI API (`api.openai.com`). In "Direct" mode the app calls OpenAI itself using an API key stored in the Keychain. | To get a structured calorie/macro estimate back |
| Scan a barcode | The barcode digits | [Open Food Facts](https://world.openfoodfacts.org) public API | To look up the product's nutrition facts |
| Search for a food by name | The search text | Open Food Facts search API (search.openfoodfacts.org; legacy world/us.openfoodfacts.org as fallback) | To find matching products. Built-in whole foods (fruit, vegetables, staples) are matched on the device and never leave it. |
| Sign in (optional) and stay signed in | See [Accounts](#accounts-and-sync-optional): your identity from the provider (email, name, provider user id) and, from then on, your log entries, favorites, goals, body stats and body scans | Free Track's account API (a Cloudflare Worker + D1 database you deploy, `server/account-api`) | To back up and sync across devices |

Nothing else is transmitted. There are no analytics, no crash-reporting SDK, no ads, and no push
notifications. Without an account, your calorie history, goals, body stats and favorites are never
uploaded.

Identifiers: photo, barcode and search requests carry no user ID, device ID or advertising ID. The proxy
sees the caller's IP address as any web server does; Open Food Facts sees the app's User-Agent string.
Account API requests carry your session token (which identifies your account) and nothing else.

## Accounts and sync (optional)

Signing in is never required. If you do (Settings > Account, or the second onboarding page):

| What | Where it goes | Notes |
|---|---|---|
| Your identity from Apple, Google or Facebook: provider user id, email (Apple may give a private relay address), display name, avatar URL | `users` / `identities` tables in the account API's D1 database | The Google / Facebook secrets live only on the Worker; no provider SDK runs in the app. Apple identity tokens are verified against Apple's public keys. |
| Log entries (name, serving, quantity, nutrition, meal, time, notes, AI confidence), favorites, goals and unit system, body stats (`UserProfile`), body scans | `documents` table, one JSON document per object, keyed by your user id | Meal **photos are never uploaded** by sync; only the entry's text and numbers. |
| Session: a 1-hour access token and a 30-day refresh token | Keychain on the phone; the refresh token's SHA-256 on the server | Logout revokes the session immediately. |

Sync runs when you sign in, when the app comes to the foreground and a few seconds after each change.
Conflicts between devices resolve by "last edit wins". Deleting an entry on one device deletes it
everywhere. **Delete account** (Settings > Account) removes the account and every document from the
server at once; your phone keeps its local copy. Signing out keeps local data too.

The Worker's Cloudflare account sees standard request logs (IP, timestamp, path). D1 data is stored
in Cloudflare's infrastructure under your Cloudflare account; see
[`../server/account-api/README.md`](../server/account-api/README.md) for deployment and retention controls.

## Retention

| Party | What they keep | For how long |
|---|---|---|
| Your phone | Log entries, photos, favorites, settings | Until you delete the entry (deleting an entry deletes its photo) or the app. CSV export is a file you own. |
| The proxy (your Cloudflare Worker) | Nothing by default. It streams the request through and does not write the image or the reply to storage. Cloudflare keeps standard request logs (IP, timestamp, status) per its own policy. | Cloudflare log retention |
| OpenAI | Every request is sent with `store: false` (the proxy forces it), so the photo is not kept as a stored response. API inputs and outputs are subject to OpenAI's [business terms](https://openai.com/policies/business-terms) and [API data usage policy](https://platform.openai.com/docs/guides/your-data); by default API data is not used to train models. Abuse-monitoring retention is time-limited (see their current policy). | Per OpenAI policy |
| Open Food Facts | Standard web-server logs. Lookups are anonymous. | Per OFF policy |
| The account API (your Cloudflare Worker + D1), only if you sign in | Identity (email, name, provider id), session hashes, and the synced documents listed above | Until you delete the account in Settings (everything is removed at once) or sign out of every device and the refresh tokens expire (30 days; documents stay until deletion) |

For App Store "App Privacy" answers this is declared as **Photos or Videos** and **Other User Content**
("collected, not linked to the user, not used for tracking, purpose: App Functionality") plus, for the
optional account, **Email Address**, **Name**, **User ID** and **Health & Fitness** ("collected, linked
to the user, not used for tracking, purpose: App Functionality"). The privacy manifest at
`FreeTrack/Resources/PrivacyInfo.xcprivacy` says the same thing in machine-readable form. See
[`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) section 3.

## Proxy vs. direct mode

The app has two ways to reach the model (Settings > Photo logging):

- **Proxy (default, recommended).** The OpenAI API key lives only on the Cloudflare Worker in
  `server/ai-proxy/`. The app sends the request to `<your-proxy>/v1/responses`; the Worker adds the
  key and forwards to OpenAI. Users never see or hold a key. The Worker can enforce a shared app token,
  rate limits and a model allow-list so a leaked proxy URL cannot drain your budget.
- **Direct.** For personal/dev use only: paste an OpenAI API key into the app; it is stored in the
  iOS Keychain and sent as a bearer token straight to `api.openai.com`. Never ship a key inside the
  binary.

### Running the proxy

Full instructions are in [`../server/ai-proxy/README.md`](../server/ai-proxy/README.md). The shape is:

```bash
cd server/ai-proxy
npm ci
npx wrangler login
npx wrangler secret put OPENAI_API_KEY        # paste the key from platform.openai.com
npx wrangler secret put APP_TOKEN            # optional shared token; paste the same value into the app
npx wrangler deploy                          # prints https://<name>.<account>.workers.dev
```

Paste that URL into Free Track > Settings > Photo logging > Proxy URL. Local development: `npx wrangler dev` and use
`http://<your-lan-ip>:8787` from a phone on the same Wi-Fi (the app only accepts `http(s)` URLs).

## Model and request shape

The app calls the OpenAI Responses API with model **`gpt-6-luna`**, a stable system prompt in
`instructions`, one image block plus one text block, reasoning effort `low`, `store: false`, and a strict
JSON-schema output so the reply is always parseable (`ARCHITECTURE.md` has the exact body).
`max_output_tokens` is 4096; a typical reply is far shorter.

## Cost estimate per photo

OpenAI list prices for `gpt-6-luna`: **$0.10 per million input tokens, $0.50 per million output tokens**.

| Component | Tokens (typical) | Cost |
|---|---|---|
| System prompt + instruction + hint text | ~1,000-2,000 input | $0.0001-0.0002 |
| Image (a 1600 px JPEG at `detail: high`; roughly one token per 32x32 patch, ~1,500-2,000 for the sizes we send) | ~1,500-2,000 input | ~$0.0002 |
| Reply: structured JSON with items, macros, confidence, clarifying question | ~600 output (plus reasoning tokens at `low` effort, billed as output) | ~$0.0003-0.0005 |
| **Total** | | **well under a tenth of a cent per photo** |

Rules of thumb: 3 photos a day is a few cents a month per user. If estimates come back sloppy, raise
`OpenAIVisionCodec.reasoningEffort` to `medium` or switch the model to `gpt-6.1-sol` ($2 / $10 per million,
still a few tenths of a cent per photo) in both the app and the Worker allow-list. Set a monthly budget under
Limits on platform.openai.com before handing the proxy URL to anyone else.

Open Food Facts is free; please respect their [API guidelines](https://openfoodfacts.github.io/openfoodfacts-server/api/)
(descriptive User-Agent, no bulk scraping).

## Your rights / how to delete everything

Delete the app: all logs, photos and settings go with it. If you signed in, first use Settings > Account
> **Delete account** so the server copy goes too (deleting the app alone leaves the server copy until
you delete the account from another device). To delete a single meal, swipe it in Today or History;
its photo is removed from disk at the same time and, when signed in, the entry is removed from the
server on the next sync. Photos already sent to OpenAI are governed by their retention policy above;
Free Track cannot recall them.
