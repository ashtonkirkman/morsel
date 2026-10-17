# Free Track AI proxy

A tiny Cloudflare Worker that sits between the Free Track iOS app and the OpenAI API so the
API key lives on the server, not on phones.

It accepts `POST /v1/responses`, adds `Authorization: Bearer <key>` from a Worker secret, and forwards
the request to `https://api.openai.com/v1/responses`. Everything else is rejected.

## Guardrails

| Check | Behaviour |
|---|---|
| Path / method | Anything other than `POST /v1/responses` → 404 |
| Body size | JSON body larger than 6 MB → 413 |
| Model | Only `gpt-6-luna` and `gpt-6.1-sol` → otherwise 400 |
| `max_output_tokens` | Capped at 8192 (set to 8192 when missing) |
| `store` | Forced to `false` so OpenAI does not keep the photo as a stored response |
| `stream` | Removed; the app never streams |
| Credentials | Client `authorization` / `x-api-key` headers are dropped; only the secret is sent upstream |
| App token | If the `APP_TOKEN` secret is set, requests must carry the same value in `x-morsel-token` (401 otherwise). Skipped when the secret is unset. |
| Rate limit | If a `RATE_LIMITER` Rate Limiting binding exists, 30 requests / 60 s per client IP → 429. Skipped when the binding is absent. |
| Passthrough | Upstream status, body, `x-request-id` and `retry-after` headers are returned as-is. |

Proxy-generated errors use the same `{ "error": { "type", "message" } }` shape as OpenAI's, so the app
shows one kind of message for both.

No CORS headers are emitted: the only client is the native app.

## Deploy

```bash
cd server/ai-proxy
npm i
npx wrangler login
npx wrangler secret put OPENAI_API_KEY          # paste your sk-... key from platform.openai.com
npx wrangler secret put APP_TOKEN              # optional shared token (any long random string)
npx wrangler deploy
```

`wrangler deploy` prints a URL like `https://freetrack-ai-proxy.<your-subdomain>.workers.dev`.
In Free Track open **Settings → Photo logging**, choose **Proxy server**, and paste that URL
(no trailing `/v1/responses`; the app appends it).

### Enabling the rate limit

Uncomment the `[[ratelimits]]` block in `wrangler.toml` and redeploy. Older Wrangler versions use the
legacy `[[unsafe.bindings]]` form with `type = "ratelimit"`; the binding name must stay `RATE_LIMITER`.

### Local development

```bash
echo 'OPENAI_API_KEY=sk-...' > .dev.vars   # git-ignored
npx wrangler dev
curl -s http://127.0.0.1:8787/v1/responses \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-6-luna","max_output_tokens":64,"reasoning":{"effort":"low"},"input":"Say hi"}'
```

## Notes

- If you set `APP_TOKEN`, paste the same value into Free Track → Settings → Photo logging → “Proxy token”
  (stored in the Keychain and sent as `x-morsel-token`).
- To try a stronger model, the app's `OpenAIVisionCodec.model` and this Worker's allow-list are the only
  two places to change.
