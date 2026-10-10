/**
 * Free Track account API — a Cloudflare Worker + D1 that gives the iOS app user accounts
 * (Sign in with Apple, Google, Facebook) and a per-user JSON document store for sync.
 *
 *   POST   /v1/auth/apple                   native Apple identity token -> session tokens
 *   GET    /v1/auth/{google|facebook}/start  ?code_challenge=&state=  -> 302 to the provider
 *   GET    /v1/auth/{google|facebook}/callback                        -> 302 to freetrack://auth/callback
 *   POST   /v1/auth/exchange                { code, codeVerifier }   -> session tokens
 *   POST   /v1/auth/refresh                 { refreshToken }         -> session tokens (rotated)
 *   POST   /v1/auth/logout                  { refreshToken }         -> 204
 *   GET    /v1/me                           Bearer                   -> user
 *   DELETE /v1/me                           Bearer                   -> 204 (account + all data gone)
 *   GET    /v1/sync/{collection}?since=ms   Bearer                   -> { documents, serverTime }
 *   PUT    /v1/sync/{collection}            Bearer { documents }     -> { accepted, serverTime }
 *   GET    /healthz
 *
 * Rate limiting: the auth endpoints use the optional RATE_LIMITER binding (20 req / 60 s per IP)
 * when it exists. Sync endpoints are only reachable with a valid session and are bounded by the
 * 500-document / 64 KB-per-document limits, so they are not separately rate limited.
 */

import { errorResponse, json } from "./http";
import { handleApple } from "./auth/apple";
import { facebook } from "./auth/facebook";
import { google } from "./auth/google";
import { handleCallback, handleExchange, handleStart, type OAuthProvider } from "./auth/oauth";
import { authenticate, handleLogout, handleRefresh, wireUser } from "./auth/session";
import { deleteUser, getUser } from "./db";
import { handlePull, handlePush } from "./sync";

export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  /** D1 binding; see wrangler.toml. */
  DB: D1Database;
  /** `npx wrangler secret put SESSION_SECRET` (any long random string, >= 16 chars). */
  SESSION_SECRET?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  FACEBOOK_APP_ID?: string;
  FACEBOOK_APP_SECRET?: string;
  /** Audience expected in Apple identity tokens. Defaults to com.ashtonkirkman.morsel. */
  APPLE_BUNDLE_ID?: string;
  /** Custom URL scheme of the iOS app (wrangler.toml [vars]). */
  APP_SCHEME?: string;
  /** Optional Rate Limiting binding; see wrangler.toml. */
  RATE_LIMITER?: RateLimiter;
}

const PROVIDERS: Record<string, OAuthProvider> = { google, facebook };

// CORS is not needed by the native app; these headers are harmless and help `wrangler dev` poking.
const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
  "access-control-allow-headers": "authorization, content-type",
};

function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}

async function rateLimited(request: Request, env: Env): Promise<Response | null> {
  if (!env.RATE_LIMITER) return null;
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  try {
    const { success } = await env.RATE_LIMITER.limit({ key: ip });
    if (!success) return errorResponse(429, "rate_limit_error", "Too many requests. Try again in a minute.");
  } catch {
    // A misconfigured binding should not take sign-in down.
  }
  return null;
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const { method } = request;
  const path = url.pathname.replace(/\/+$/, "") || "/";

  if (method === "OPTIONS") return new Response(null, { status: 204 });
  if (path === "/healthz" && method === "GET") return json({ ok: true });

  // ---- auth -------------------------------------------------------------------------------
  if (path.startsWith("/v1/auth/")) {
    const limited = await rateLimited(request, env);
    if (limited) return limited;

    if (path === "/v1/auth/apple" && method === "POST") return handleApple(request, env);
    if (path === "/v1/auth/exchange" && method === "POST") return handleExchange(request, env);
    if (path === "/v1/auth/refresh" && method === "POST") return handleRefresh(request, env);
    if (path === "/v1/auth/logout" && method === "POST") return handleLogout(request, env);

    const match = /^\/v1\/auth\/(google|facebook)\/(start|callback)$/.exec(path);
    if (match && method === "GET") {
      const provider = PROVIDERS[match[1]];
      return match[2] === "start" ? handleStart(request, env, provider) : handleCallback(request, env, provider);
    }
    return errorResponse(404, "not_found_error", "Not found.");
  }

  // ---- authenticated ----------------------------------------------------------------------
  if (path === "/v1/me" || path.startsWith("/v1/sync/")) {
    const ctx = await authenticate(request, env);
    if (ctx instanceof Response) return ctx;

    if (path === "/v1/me" && method === "GET") {
      const user = await getUser(env.DB, ctx.userId);
      if (!user) return errorResponse(404, "not_found_error", "Account no longer exists.");
      return json(await wireUser(env, user));
    }
    if (path === "/v1/me" && method === "DELETE") {
      await deleteUser(env.DB, ctx.userId);
      return new Response(null, { status: 204 });
    }
    const sync = /^\/v1\/sync\/([^/]+)$/.exec(path);
    if (sync) {
      const collection = decodeURIComponent(sync[1]);
      if (method === "GET") return handlePull(env, ctx.userId, collection, url);
      if (method === "PUT") return handlePush(env, ctx.userId, collection, request);
      return errorResponse(405, "invalid_request_error", "Use GET or PUT.");
    }
  }

  return errorResponse(404, "not_found_error", "Not found.");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return withCors(await route(request, env));
    } catch (err) {
      console.error("unhandled", err instanceof Error ? err.stack ?? err.message : err);
      return withCors(errorResponse(500, "api_error", "Internal error."));
    }
  },
} satisfies ExportedHandler<Env>;
