# AI and data: what leaves the device

Morsel is a local-first app. Everything you log lives in a SwiftData store on the phone, photos live in
the app's Application Support folder, and goals/preferences live in UserDefaults. Three actions send data
off the device, and only when you start them.

## What is sent, where, and why

| When you... | What leaves the phone | Goes to | Why |
|---|---|---|---|
| Snap or pick a meal photo | The photo, downscaled to at most 1600 px on the long edge and JPEG-compressed (~150-400 KB), plus the optional hint text you type ("two slices", "no dressing") and your answer to the clarifying question | Morsel's Claude proxy (a Cloudflare Worker you deploy), which forwards it to the Anthropic API (`api.anthropic.com`). In "Direct" mode the app calls Anthropic itself using an API key stored in the Keychain. | To get a structured calorie/macro estimate back |
| Scan a barcode | The barcode digits | [Open Food Facts](https://world.openfoodfacts.org) public API | To look up the product's nutrition facts |
| Search for a food by name | The search text | Open Food Facts public API | To find matching products |

Nothing else is transmitted. There are no analytics, no crash-reporting SDK, no ads, no account, and
no push notifications. Your calorie history, goals, body stats and favorites are never uploaded.

Identifiers: requests carry no user ID, device ID or advertising ID. The proxy sees the caller's IP
address as any web server does; Open Food Facts sees the app's User-Agent string.

## Retention

| Party | What they keep | For how long |
|---|---|---|
| Your phone | Log entries, photos, favorites, settings | Until you delete the entry (deleting an entry deletes its photo) or the app. CSV export is a file you own. |
| The proxy (your Cloudflare Worker) | Nothing by default. It streams the request through and does not write the image or the reply to storage. Cloudflare keeps standard request logs (IP, timestamp, status) per its own policy. | Cloudflare log retention |
| Anthropic | API inputs and outputs are subject to Anthropic's [commercial terms](https://www.anthropic.com/legal/commercial-terms) and [privacy policy](https://www.anthropic.com/legal/privacy); by default they are not used to train models. Retention for trust-and-safety purposes is time-limited (see their current policy). | Per Anthropic policy |
| Open Food Facts | Standard web-server logs. Lookups are anonymous. | Per OFF policy |

For App Store "App Privacy" answers this is declared as **Photos or Videos** and **Other User Content**,
both "collected, not linked to the user, not used for tracking, purpose: App Functionality". The
privacy manifest at `Morsel/Resources/PrivacyInfo.xcprivacy` says the same thing in machine-readable
form. See [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) section 3.

## Proxy vs. direct mode

The app has two ways to reach Claude (Settings > AI):

- **Proxy (default, recommended).** The Anthropic API key lives only on the Cloudflare Worker in
  `server/claude-proxy/`. The app sends the request to `<your-proxy>/v1/messages`; the Worker adds the
  key and forwards to Anthropic. Users never see or hold a key. The Worker can enforce rate limits and
  a per-day cap so a leaked proxy URL cannot drain your budget.
- **Direct.** For personal/dev use only: paste an Anthropic API key into the app; it is stored in the
  iOS Keychain and sent as `x-api-key` straight to `api.anthropic.com`. Never ship a key inside the
  binary.

### Running the proxy

The proxy is written by the server agent; full instructions are in
[`../server/claude-proxy/README.md`](../server/claude-proxy/README.md). The shape is:

```bash
cd server/claude-proxy
npm ci
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY      # paste the key from console.anthropic.com
npx wrangler deploy                            # prints https://<name>.<account>.workers.dev
```

Paste that URL into Morsel > Settings > AI > Proxy URL. Local development: `npx wrangler dev` and use
`http://<your-lan-ip>:8787` from a phone on the same Wi-Fi (the app only accepts `http(s)` URLs).

## Model and request shape

The app calls the Messages API with model **`claude-opus-5`**, a stable system prompt marked for prompt
caching, one image block plus one text block, and a JSON-schema structured output so the reply is always
parseable (`ARCHITECTURE.md` has the exact body). Thinking is on by default for this model and left at
its default. `max_tokens` is 4096; a typical reply is far shorter.

## Cost estimate per photo

Anthropic list prices for `claude-opus-5` (first-party API): **$5 per million input tokens, $25 per
million output tokens**.

| Component | Tokens (typical) | Cost |
|---|---|---|
| System prompt + instruction + hint text | ~1,000-2,000 input | $0.005-0.010 |
| Image (a 1600 px JPEG downscaled by the API; roughly (w x h)/750 tokens, ~1,500 for the sizes we send) | ~1,500 input | ~$0.0075 |
| Reply: structured JSON with items, macros, confidence, clarifying question | ~600 output (plus any thinking tokens, billed as output) | ~$0.015 |
| **Total** | | **roughly $0.02-0.03 per photo** |

Rules of thumb: 3 photos a day is about $2-3 a month per user. Prompt caching on the system prompt
cuts the first row by up to 90% on cache hits; the image is never cached because every photo is
different. Thinking adds output tokens; if bills run high, set `output_config.effort` to `low` in the
proxy or app rather than switching models. Set a spend limit in the Anthropic console before handing the
proxy URL to anyone else.

Open Food Facts is free; please respect their [API guidelines](https://openfoodfacts.github.io/openfoodfacts-server/api/)
(descriptive User-Agent, no bulk scraping).

## Your rights / how to delete everything

Delete the app: all logs, photos and settings go with it (there is no cloud copy). To delete a single
meal, swipe it in Today or History; its photo is removed from disk at the same time. Photos already
sent to Anthropic are governed by their retention policy above; Morsel cannot recall them.
