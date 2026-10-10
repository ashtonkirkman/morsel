/**
 * Minimal JOSE helpers on WebCrypto: base64url, HS256 app tokens, RS256 verification for
 * provider id_tokens (Apple / Google JWKS), hashing and random tokens. No dependencies.
 */

export type JsonObject = Record<string, unknown>;

export interface JwtPayload extends JsonObject {
  iss?: string;
  sub?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  nbf?: number;
}

export interface JwtHeader extends JsonObject {
  alg?: string;
  kid?: string;
  typ?: string;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function utf8(s: string): Uint8Array {
  return encoder.encode(s);
}

export function base64UrlEncode(input: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof input === "string" ? utf8(input) : input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64UrlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function base64UrlDecodeToString(s: string): string {
  return decoder.decode(base64UrlDecode(s));
}

/** Cryptographically random token, base64url (default 32 bytes = 43 chars). */
export function randomToken(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return base64UrlEncode(buf);
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", utf8(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Base64Url(s: string): Promise<string> {
  return base64UrlEncode(await crypto.subtle.digest("SHA-256", utf8(s)));
}

/** Constant-time string comparison so token checks do not leak length/prefix timing. */
export function safeEqual(a: string, b: string): boolean {
  const ab = utf8(a);
  const bb = utf8(b);
  if (ab.byteLength !== bb.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < ab.byteLength; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function hmacSha256Hex(secret: string, data: string): Promise<string> {
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, utf8(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Sign an HS256 JWT. `payload` should already contain `exp` (seconds) when it must expire. */
export async function signHS256(payload: JwtPayload, secret: string): Promise<string> {
  const header = base64UrlEncode(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64UrlEncode(JSON.stringify(payload));
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, utf8(`${header}.${body}`));
  return `${header}.${body}.${base64UrlEncode(sig)}`;
}

export function decodeJwt(token: string): { header: JwtHeader; payload: JwtPayload; signingInput: string; signature: Uint8Array } | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const header = JSON.parse(base64UrlDecodeToString(parts[0])) as JwtHeader;
    const payload = JSON.parse(base64UrlDecodeToString(parts[1])) as JwtPayload;
    if (typeof header !== "object" || header === null || typeof payload !== "object" || payload === null) return null;
    return { header, payload, signingInput: `${parts[0]}.${parts[1]}`, signature: base64UrlDecode(parts[2]) };
  } catch {
    return null;
  }
}

/** Verify an HS256 JWT's signature and time claims. Returns the payload or null. */
export async function verifyHS256(token: string, secret: string, nowSeconds = Math.floor(Date.now() / 1000)): Promise<JwtPayload | null> {
  const decoded = decodeJwt(token);
  if (!decoded || decoded.header.alg !== "HS256") return null;
  const key = await hmacKey(secret);
  const ok = await crypto.subtle.verify("HMAC", key, decoded.signature, utf8(decoded.signingInput));
  if (!ok) return null;
  return checkTimeClaims(decoded.payload, nowSeconds) ? decoded.payload : null;
}

export function checkTimeClaims(payload: JwtPayload, nowSeconds: number, leewaySeconds = 60): boolean {
  if (typeof payload.exp === "number" && nowSeconds > payload.exp + leewaySeconds) return false;
  if (typeof payload.nbf === "number" && nowSeconds + leewaySeconds < payload.nbf) return false;
  return true;
}

export interface Jwk extends JsonObject {
  kty?: string;
  kid?: string;
  use?: string;
  alg?: string;
  n?: string;
  e?: string;
}

/** Verify an RS256 JWT against a JWK set (matched by `kid`). Returns the payload or null. */
export async function verifyRS256(token: string, keys: Jwk[], nowSeconds = Math.floor(Date.now() / 1000)): Promise<JwtPayload | null> {
  const decoded = decodeJwt(token);
  if (!decoded || decoded.header.alg !== "RS256") return null;
  const jwk = keys.find((k) => k.kid === decoded.header.kid && k.kty === "RSA");
  if (!jwk || jwk.kty !== "RSA" || !jwk.n || !jwk.e) return null;
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      "jwk",
      { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    return null;
  }
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, decoded.signature, utf8(decoded.signingInput));
  if (!ok) return null;
  return checkTimeClaims(decoded.payload, nowSeconds) ? decoded.payload : null;
}

export function audienceMatches(aud: string | string[] | undefined, expected: string): boolean {
  if (typeof aud === "string") return aud === expected;
  if (Array.isArray(aud)) return aud.includes(expected);
  return false;
}
