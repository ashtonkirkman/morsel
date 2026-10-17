/**
 * Free Track AI proxy — a Cloudflare Worker that holds the OpenAI API key so the iOS app never does.
 *
 * Forwards POST /v1/responses to api.openai.com with guardrails:
 *   - only POST /v1/responses (everything else 404)
 *   - JSON body ≤ 6 MB, model allow-list, max_output_tokens cap, store forced to false
 *   - client-supplied credentials are never forwarded
 *   - optional shared app token (APP_TOKEN secret ⇄ x-morsel-token header)
 *   - optional per-IP rate limit via a Rate Limiting binding (RATE_LIMITER)
 */

export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  /** `npx wrangler secret put OPENAI_API_KEY` */
  OPENAI_API_KEY?: string;
  /** Optional: `npx wrangler secret put APP_TOKEN`; when set, clients must send it as `x-morsel-token`. */
  APP_TOKEN?: string;
  /** Optional Rate Limiting binding; see wrangler.toml. */
  RATE_LIMITER?: RateLimiter;
}

const UPSTREAM = "https://api.openai.com/v1/responses";
const ALLOWED_MODELS: ReadonlySet<string> = new Set(["gpt-6-luna", "gpt-6.1-sol"]);
const MAX_BODY_BYTES = 6 * 1024 * 1024;
const MAX_OUTPUT_TOKENS_CAP = 8192;

type JsonObject = Record<string, unknown>;

/** Same shape as an OpenAI error body so the app's parser handles proxy and upstream errors alike. */
function errorResponse(status: number, type: string, message: string): Response {
  return new Response(JSON.stringify({ error: { type, message, code: null, param: null } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/** Constant-time string comparison so token checks do not leak length/prefix timing. */
function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < ab.byteLength; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function readJsonBody(request: Request): Promise<JsonObject | Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return errorResponse(413, "request_too_large", "Request body exceeds 6 MB.");
  }
  const raw = await request.arrayBuffer();
  if (raw.byteLength > MAX_BODY_BYTES) {
    return errorResponse(413, "request_too_large", "Request body exceeds 6 MB.");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return errorResponse(400, "invalid_request_error", "Body must be valid JSON.");
  }
  if (!isJsonObject(parsed)) {
    return errorResponse(400, "invalid_request_error", "Body must be a JSON object.");
  }
  return parsed;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/responses" || request.method !== "POST") {
      return errorResponse(404, "not_found_error", "Not found.");
    }

    if (!env.OPENAI_API_KEY) {
      return errorResponse(500, "api_error", "Proxy is not configured: OPENAI_API_KEY secret is missing.");
    }

    // Optional shared app token.
    if (env.APP_TOKEN) {
      const provided = request.headers.get("x-morsel-token") ?? "";
      if (!safeEqual(provided, env.APP_TOKEN)) {
        return errorResponse(401, "authentication_error", "Missing or invalid app token.");
      }
    }

    // Optional per-IP rate limit (binding may be absent before configuration).
    if (env.RATE_LIMITER) {
      const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
      try {
        const { success } = await env.RATE_LIMITER.limit({ key: ip });
        if (!success) {
          return errorResponse(429, "rate_limit_error", "Too many requests. Try again in a minute.");
        }
      } catch {
        // A misconfigured binding should not take the proxy down.
      }
    }

    const body = await readJsonBody(request);
    if (body instanceof Response) return body;

    const model = body.model;
    if (typeof model !== "string" || !ALLOWED_MODELS.has(model)) {
      return errorResponse(400, "invalid_request_error", `model must be one of: ${[...ALLOWED_MODELS].join(", ")}.`);
    }

    const maxOutputTokens = body.max_output_tokens;
    if (typeof maxOutputTokens !== "number" || !Number.isFinite(maxOutputTokens) || maxOutputTokens < 1) {
      body.max_output_tokens = MAX_OUTPUT_TOKENS_CAP;
    } else if (maxOutputTokens > MAX_OUTPUT_TOKENS_CAP) {
      body.max_output_tokens = MAX_OUTPUT_TOKENS_CAP;
    }

    // Never let OpenAI retain the photo as a stored response, whatever the client asked for.
    body.store = false;
    // Streaming is not something the app does; keep the proxy a simple request/response hop.
    delete body.stream;

    // Fresh header set: client-supplied authorization / x-api-key never reach upstream.
    const headers = new Headers({
      "content-type": "application/json",
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
    });

    let upstream: Response;
    try {
      upstream = await fetch(UPSTREAM, { method: "POST", headers, body: JSON.stringify(body) });
    } catch {
      return errorResponse(502, "api_error", "Could not reach the OpenAI API.");
    }

    const out = new Headers({
      "content-type": upstream.headers.get("content-type") ?? "application/json",
    });
    const requestId = upstream.headers.get("x-request-id");
    if (requestId) out.set("x-request-id", requestId);
    const retryAfter = upstream.headers.get("retry-after");
    if (retryAfter) out.set("retry-after", retryAfter);

    return new Response(upstream.body, { status: upstream.status, headers: out });
  },
} satisfies ExportedHandler<Env>;
