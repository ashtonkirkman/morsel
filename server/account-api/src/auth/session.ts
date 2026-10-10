/**
 * App sessions.
 *
 *   access token  : HS256 JWT, 1 hour, claims { sub: user id, sid: session id, typ: "access" }.
 *                   Signed with SESSION_SECRET; verified on every request AND checked against the
 *                   sessions row so logout / account deletion take effect immediately.
 *   refresh token : 32 random bytes (base64url), 30 days, stored as SHA-256 in `sessions`.
 *                   POST /v1/auth/refresh rotates it in place (old value stops working).
 */

import { errorResponse, json, readJsonBody } from "../http";
import type { Env } from "../index";
import { getSession, getSessionByRefreshHash, getUser, insertSession, listProviders, revokeSession, rotateSession, type UserRow } from "../db";
import { randomToken, sha256Hex, signHS256, verifyHS256 } from "../jwt";

export const ACCESS_TTL_SECONDS = 60 * 60;
export const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export interface AuthContext {
  userId: string;
  sessionId: string;
}

export interface WireUser {
  id: string;
  displayName: string | null;
  email: string | null;
  avatarUrl: string | null;
  createdAt: number;
  providers: string[];
}

export async function wireUser(env: Env, user: UserRow): Promise<WireUser> {
  return {
    id: user.id,
    displayName: user.display_name,
    email: user.email,
    avatarUrl: user.avatar_url,
    createdAt: user.created_at,
    providers: await listProviders(env.DB, user.id),
  };
}

export function requireSecret(env: Env): string | Response {
  if (!env.SESSION_SECRET || env.SESSION_SECRET.length < 16) {
    return errorResponse(500, "api_error", "Server is not configured: SESSION_SECRET secret is missing.");
  }
  return env.SESSION_SECRET;
}

/** Create a session row and return the token bundle the app stores. */
export async function issueSession(env: Env, user: UserRow, now = Date.now()): Promise<Response> {
  const secret = requireSecret(env);
  if (secret instanceof Response) return secret;
  const sessionId = crypto.randomUUID();
  const refreshToken = randomToken(32);
  const refreshExpiresAt = now + REFRESH_TTL_MS;
  await insertSession(env.DB, {
    id: sessionId,
    user_id: user.id,
    refresh_token_hash: await sha256Hex(refreshToken),
    created_at: now,
    expires_at: refreshExpiresAt,
    revoked_at: null,
  });
  return tokenResponse(env, secret, user, sessionId, refreshToken, refreshExpiresAt, now);
}

async function tokenResponse(env: Env, secret: string, user: UserRow, sessionId: string, refreshToken: string, refreshExpiresAt: number, now: number): Promise<Response> {
  const iat = Math.floor(now / 1000);
  const exp = iat + ACCESS_TTL_SECONDS;
  const accessToken = await signHS256({ sub: user.id, sid: sessionId, typ: "access", iat, exp }, secret);
  return json({
    accessToken,
    accessExpiresAt: exp * 1000,
    refreshToken,
    refreshExpiresAt,
    user: await wireUser(env, user),
  });
}

/** Bearer-token guard for every /v1/me and /v1/sync route. */
export async function authenticate(request: Request, env: Env): Promise<AuthContext | Response> {
  const secret = requireSecret(env);
  if (secret instanceof Response) return secret;
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return errorResponse(401, "authentication_error", "Missing bearer token.");
  const payload = await verifyHS256(match[1].trim(), secret);
  if (!payload || payload.typ !== "access" || typeof payload.sub !== "string" || typeof payload.sid !== "string") {
    return errorResponse(401, "authentication_error", "Invalid or expired access token.");
  }
  const session = await getSession(env.DB, payload.sid);
  if (!session || session.revoked_at !== null || session.user_id !== payload.sub || session.expires_at < Date.now()) {
    return errorResponse(401, "authentication_error", "Session is no longer valid.");
  }
  return { userId: payload.sub, sessionId: payload.sid };
}

/** POST /v1/auth/refresh { refreshToken } */
export async function handleRefresh(request: Request, env: Env): Promise<Response> {
  const secret = requireSecret(env);
  if (secret instanceof Response) return secret;
  const body = await readJsonBody(request);
  if (body instanceof Response) return body;
  const refreshToken = typeof body.refreshToken === "string" ? body.refreshToken : "";
  if (refreshToken.length < 32) return errorResponse(400, "invalid_request_error", "refreshToken is required.");
  const now = Date.now();
  const session = await getSessionByRefreshHash(env.DB, await sha256Hex(refreshToken));
  if (!session || session.revoked_at !== null || session.expires_at < now) {
    return errorResponse(401, "authentication_error", "Refresh token is invalid, expired or revoked.");
  }
  const user = await getUser(env.DB, session.user_id);
  if (!user) return errorResponse(401, "authentication_error", "Account no longer exists.");
  const next = randomToken(32);
  const expiresAt = now + REFRESH_TTL_MS;
  await rotateSession(env.DB, session.id, await sha256Hex(next), expiresAt);
  return tokenResponse(env, secret, user, session.id, next, expiresAt, now);
}

/** POST /v1/auth/logout { refreshToken } (or Bearer access token). Always 204. */
export async function handleLogout(request: Request, env: Env): Promise<Response> {
  const now = Date.now();
  const body = await readJsonBody(request).catch(() => null);
  const refreshToken = body && !(body instanceof Response) && typeof body.refreshToken === "string" ? body.refreshToken : "";
  if (refreshToken) {
    const session = await getSessionByRefreshHash(env.DB, await sha256Hex(refreshToken));
    if (session) await revokeSession(env.DB, session.id, now);
  } else {
    const ctx = await authenticate(request, env);
    if (!(ctx instanceof Response)) await revokeSession(env.DB, ctx.sessionId, now);
  }
  return new Response(null, { status: 204 });
}
