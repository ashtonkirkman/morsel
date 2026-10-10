/**
 * Sign in with Apple (native). The app sends the identity token it got from
 * ASAuthorizationAppleIDProvider; we verify it against Apple's JWKS and upsert the user.
 *
 * The authorization code and full name are accepted too: the name only arrives on the very
 * first sign-in (Apple never sends it again), the code is currently not exchanged (that needs a
 * Sign in with Apple private key; see README "Token revocation").
 */

import { errorResponse, isJsonObject, optionalString, readJsonBody } from "../http";
import type { Env } from "../index";
import { upsertIdentity, type ProviderProfile } from "../db";
import { audienceMatches, verifyRS256, type Jwk, type JwtPayload } from "../jwt";
import { issueSession } from "./session";

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
export const DEFAULT_BUNDLE_ID = "com.ashtonkirkman.morsel";

export type FetchKeys = () => Promise<Jwk[]>;

let cachedKeys: { keys: Jwk[]; fetchedAt: number } | null = null;
const JWKS_TTL_MS = 6 * 60 * 60 * 1000;

/** Apple's public keys, cached for six hours per isolate. */
export const fetchAppleKeys: FetchKeys = async () => {
  if (cachedKeys && Date.now() - cachedKeys.fetchedAt < JWKS_TTL_MS) return cachedKeys.keys;
  const res = await fetch(APPLE_JWKS_URL, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`Apple JWKS ${res.status}`);
  const body = (await res.json()) as { keys?: Jwk[] };
  const keys = Array.isArray(body.keys) ? body.keys : [];
  cachedKeys = { keys, fetchedAt: Date.now() };
  return keys;
};

export interface AppleClaims {
  sub: string;
  email?: string;
  emailVerified: boolean;
  isPrivateEmail: boolean;
  payload: JwtPayload;
}

export interface VerifyOptions {
  bundleId: string;
  fetchKeys?: FetchKeys;
  nowSeconds?: number;
}

/**
 * Verify an Apple identity token: RS256 signature (JWKS by kid), iss, aud (= bundle id), exp.
 * Returns null on any failure. Retries once with fresh keys when the kid is unknown (rotation).
 */
export async function verifyAppleIdentityToken(token: string, options: VerifyOptions): Promise<AppleClaims | null> {
  const fetchKeys = options.fetchKeys ?? fetchAppleKeys;
  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  let payload = await verifyRS256(token, await fetchKeys(), now);
  if (!payload && fetchKeys === fetchAppleKeys) {
    cachedKeys = null;
    payload = await verifyRS256(token, await fetchKeys(), now);
  }
  if (!payload) return null;
  if (payload.iss !== APPLE_ISSUER) return null;
  if (!audienceMatches(payload.aud, options.bundleId)) return null;
  if (typeof payload.exp !== "number") return null;
  if (typeof payload.sub !== "string" || payload.sub.length === 0) return null;
  const email = optionalString(payload.email);
  const verifiedRaw = payload.email_verified;
  const emailVerified = verifiedRaw === true || verifiedRaw === "true";
  const privateRaw = payload.is_private_email;
  return { sub: payload.sub, email, emailVerified, isPrivateEmail: privateRaw === true || privateRaw === "true", payload };
}

/** POST /v1/auth/apple { identityToken, authorizationCode?, fullName?: { givenName?, familyName? } } */
export async function handleApple(request: Request, env: Env): Promise<Response> {
  const body = await readJsonBody(request);
  if (body instanceof Response) return body;
  const identityToken = optionalString(body.identityToken);
  if (!identityToken) return errorResponse(400, "invalid_request_error", "identityToken is required.");
  let claims: AppleClaims | null;
  try {
    claims = await verifyAppleIdentityToken(identityToken, { bundleId: env.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID });
  } catch {
    return errorResponse(502, "api_error", "Could not fetch Apple's signing keys.");
  }
  if (!claims) return errorResponse(401, "authentication_error", "Apple identity token was rejected.");

  let name: string | undefined;
  if (isJsonObject(body.fullName)) {
    const given = optionalString(body.fullName.givenName);
    const family = optionalString(body.fullName.familyName);
    name = [given, family].filter(Boolean).join(" ") || undefined;
  }
  const profile: ProviderProfile = {
    providerUserId: claims.sub,
    email: claims.email,
    emailVerified: claims.emailVerified,
    name,
    raw: { sub: claims.sub, email: claims.email, is_private_email: claims.isPrivateEmail },
  };
  const user = await upsertIdentity(env.DB, "apple", profile, Date.now());
  return issueSession(env, user);
}
