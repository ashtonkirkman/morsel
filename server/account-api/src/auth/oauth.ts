/**
 * Shared authorization-code + PKCE plumbing for the web providers (Google, Facebook).
 *
 *   app  ──ASWebAuthenticationSession──▶ GET /v1/auth/{p}/start?code_challenge=C&state=S
 *        Worker packs {C, S, provider} into a signed, 10-minute JWT and uses *that* as the
 *        provider's `state` (stateless; nothing stored yet) ──▶ provider consent page
 *   provider ──▶ GET /v1/auth/{p}/callback?code=...&state=<signed>
 *        Worker verifies the state, exchanges the code server-side with the client secret,
 *        fetches the profile, upserts the user, stores a one-time code bound to C, and
 *        redirects to  freetrack://auth/callback?code=<one-time>&state=S
 *   app  ──▶ POST /v1/auth/exchange { code, codeVerifier }
 *        Worker checks SHA256(codeVerifier) == C, deletes the code, issues session tokens.
 *
 * Tokens therefore never travel in a URL, and a leaked callback URL is useless without the
 * verifier that only the app holds.
 */

import { errorResponse, optionalString, readJsonBody } from "../http";
import type { Env } from "../index";
import { consumeAuthCode, deleteExpiredAuthCodes, getUser, insertAuthCode, upsertIdentity, type ProviderProfile } from "../db";
import { randomToken, sha256Base64Url, sha256Hex, signHS256, verifyHS256 } from "../jwt";
import { issueSession, requireSecret } from "./session";

export interface OAuthProvider {
  name: "google" | "facebook";
  /** True when the required secrets are configured. */
  isConfigured(env: Env): boolean;
  /** Provider consent URL for the given redirect URI and (signed) state. */
  authorizeUrl(env: Env, redirectUri: string, state: string): string;
  /** Exchange the provider's code for a profile. Throws on failure. */
  exchangeCode(env: Env, code: string, redirectUri: string): Promise<ProviderProfile>;
}

const STATE_TTL_SECONDS = 10 * 60;
const ONE_TIME_CODE_TTL_MS = 5 * 60 * 1000;
const CODE_CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
const CODE_VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;

export function callbackUrl(requestUrl: URL, provider: string): string {
  return `${requestUrl.origin}/v1/auth/${provider}/callback`;
}

export function appRedirect(env: Env, params: Record<string, string>): Response {
  const scheme = (env.APP_SCHEME || "freetrack").replace(/[^a-z0-9.+-]/gi, "");
  const query = new URLSearchParams(params).toString();
  return Response.redirect(`${scheme}://auth/callback?${query}`, 302);
}

/** GET /v1/auth/{provider}/start?code_challenge=...&state=... */
export async function handleStart(request: Request, env: Env, provider: OAuthProvider): Promise<Response> {
  const secret = requireSecret(env);
  if (secret instanceof Response) return secret;
  if (!provider.isConfigured(env)) return errorResponse(503, "api_error", `${provider.name} sign-in is not configured on this server.`);
  const url = new URL(request.url);
  const challenge = url.searchParams.get("code_challenge") ?? "";
  const appState = url.searchParams.get("state") ?? "";
  if (!CODE_CHALLENGE.test(challenge)) return errorResponse(400, "invalid_request_error", "code_challenge must be a base64url SHA-256 (S256).");
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(appState)) return errorResponse(400, "invalid_request_error", "state is required.");
  const iat = Math.floor(Date.now() / 1000);
  const signedState = await signHS256({ typ: "oauth_state", p: provider.name, cc: challenge, st: appState, iat, exp: iat + STATE_TTL_SECONDS }, secret);
  return Response.redirect(provider.authorizeUrl(env, callbackUrl(url, provider.name), signedState), 302);
}

/** GET /v1/auth/{provider}/callback?code=...&state=... (the provider redirects here). */
export async function handleCallback(request: Request, env: Env, provider: OAuthProvider): Promise<Response> {
  const secret = requireSecret(env);
  if (secret instanceof Response) return secret;
  const url = new URL(request.url);
  const signedState = url.searchParams.get("state") ?? "";
  const statePayload = await verifyHS256(signedState, secret);
  if (!statePayload || statePayload.typ !== "oauth_state" || statePayload.p !== provider.name || typeof statePayload.cc !== "string" || typeof statePayload.st !== "string") {
    // Without a valid state we do not even know where to send the user; plain error page.
    return errorResponse(400, "invalid_request_error", "Sign-in state is missing or expired. Please try again from the app.");
  }
  const appState = statePayload.st;
  const providerError = url.searchParams.get("error");
  if (providerError) {
    return appRedirect(env, { error: providerError === "access_denied" ? "cancelled" : "provider_error", state: appState });
  }
  const code = url.searchParams.get("code") ?? "";
  if (!code) return appRedirect(env, { error: "missing_code", state: appState });

  let profile: ProviderProfile;
  try {
    profile = await provider.exchangeCode(env, code, callbackUrl(url, provider.name));
  } catch (err) {
    console.error(`${provider.name} exchange failed`, err instanceof Error ? err.message : err);
    return appRedirect(env, { error: "exchange_failed", state: appState });
  }
  const now = Date.now();
  const user = await upsertIdentity(env.DB, provider.name, profile, now);
  const oneTimeCode = randomToken(32);
  await insertAuthCode(env.DB, {
    code_hash: await sha256Hex(oneTimeCode),
    user_id: user.id,
    code_challenge: statePayload.cc,
    created_at: now,
    expires_at: now + ONE_TIME_CODE_TTL_MS,
  });
  // Opportunistic cleanup; failures are irrelevant.
  await deleteExpiredAuthCodes(env.DB, now).catch(() => undefined);
  return appRedirect(env, { code: oneTimeCode, state: appState });
}

/** POST /v1/auth/exchange { code, codeVerifier } -> session tokens. */
export async function handleExchange(request: Request, env: Env): Promise<Response> {
  const body = await readJsonBody(request);
  if (body instanceof Response) return body;
  const code = optionalString(body.code);
  const verifier = optionalString(body.codeVerifier);
  if (!code || !verifier || !CODE_VERIFIER.test(verifier)) {
    return errorResponse(400, "invalid_request_error", "code and codeVerifier are required.");
  }
  const row = await consumeAuthCode(env.DB, await sha256Hex(code));
  if (!row) return errorResponse(401, "authentication_error", "Code is invalid or was already used.");
  const now = Date.now();
  if (row.expires_at < now) return errorResponse(401, "authentication_error", "Code expired. Please sign in again.");
  const expected = await sha256Base64Url(verifier);
  if (expected !== row.code_challenge) return errorResponse(401, "authentication_error", "PKCE verification failed.");
  const user = await getUser(env.DB, row.user_id);
  if (!user) return errorResponse(401, "authentication_error", "Account no longer exists.");
  return issueSession(env, user, now);
}

/** PKCE check as a pure function for tests. */
export async function pkceMatches(verifier: string, challenge: string): Promise<boolean> {
  if (!CODE_VERIFIER.test(verifier)) return false;
  return (await sha256Base64Url(verifier)) === challenge;
}
