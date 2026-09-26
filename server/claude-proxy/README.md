# Morsel Claude proxy

A tiny Cloudflare Worker that sits between the Morsel iOS app and the Anthropic API so the
API key lives on the server, not on phones.

It accepts `POST /v1/messages`, adds `x-api-key` from a Worker secret, and forwards the request
to `https://api.anthropic.com/v1/messages`. Everything else is rejected.

## Guardrails

| Check | Behaviour |
|---|---|
| Path / method | Anything other than `POST /v1/messages` → 404 |
| Body size | JSON body larger than 6 MB → 413 |
| Model | Only `claude-opus-5` and `claude-sonnet-5` → otherwise 400 |
| `max_tokens` | Capped at 8192 (set to 8192 when missing) |
| Credentials | Client `x-api-key` / `authorization` headers are dropped; only the secret is sent upstream |
| App token | If the `APP_TOKEN` secret is set, requests must carry the same value in `x-morsel-token` (401 otherwise). Skipped when the secret is unset. |
| Rate limit | If a `RATE_LIMITER` Rate Limiting binding exists, 30 requests / 60 s per client IP → 429. Skipped when the binding is absent. |
| Passthrough | Upstream status, body, `request-id` and `retry-after` headers are returned as-is; `anthropic-version` and `anthropic-beta` request headers are forwarded. |

No CORS headers are emitted: the only client is the native app.

## Deploy

```bash
cd server/claude-proxy
npm i
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY      # paste your sk-ant-... key
npx wrangler secret put APP_TOKEN              # optional shared token (any long random string)
npx wrangler deploy
```

`wrangler deploy` prints a URL like `https://morsel-claude-proxy.<your-subdomain>.workers.dev`.
In Morsel open **Settings → Photo logging**, choose **Proxy server**, and paste that URL
(no trailing `/v1/messages`; the app appends it).

### Enabling the rate limit

Uncomment the `[[ratelimits]]` block in `wrangler.toml` and redeploy. Older Wrangler versions use the
legacy `[[unsafe.bindings]]` form with `type = "ratelimit"`; the binding name must stay `RATE_LIMITER`.

### Local development

```bash
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .dev.vars   # git-ignored
npx wrangler dev
curl -s http://127.0.0.1:8787/v1/messages \
  -H 'content-type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"claude-opus-5","max_tokens":64,"messages":[{"role":"user","content":"Say hi"}]}'
```

## Notes

- The iOS app does not yet send `x-morsel-token`; adding a `.proxyToken` Keychain key and a
  Settings field is a follow-up. Until then leave `APP_TOKEN` unset.
- Streaming requests (`"stream": true`) are passed through untouched; the app does not use them.
