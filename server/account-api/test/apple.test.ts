import { beforeAll, describe, expect, it } from "vitest";
import { APPLE_ISSUER, verifyAppleIdentityToken } from "../src/auth/apple";
import { base64UrlEncode, type Jwk } from "../src/jwt";

const BUNDLE = "com.ashtonkirkman.morsel";
const NOW = 1_800_000_000;

let privateKey: CryptoKey;
let jwks: Jwk[];

async function makeToken(payload: Record<string, unknown>, header: Record<string, unknown> = { alg: "RS256", kid: "test-kid" }, key = privateKey): Promise<string> {
  const h = base64UrlEncode(JSON.stringify(header));
  const p = base64UrlEncode(JSON.stringify(payload));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${base64UrlEncode(sig)}`;
}

const validPayload = () => ({
  iss: APPLE_ISSUER,
  aud: BUNDLE,
  sub: "001234.abcdef.5678",
  email: "hidden@privaterelay.appleid.com",
  email_verified: "true",
  is_private_email: "true",
  iat: NOW - 10,
  exp: NOW + 600,
});

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  privateKey = pair.privateKey;
  const pub = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  jwks = [{ kty: "RSA", kid: "test-kid", use: "sig", alg: "RS256", n: pub.n, e: pub.e }];
});

describe("verifyAppleIdentityToken", () => {
  const options = () => ({ bundleId: BUNDLE, fetchKeys: async () => jwks, nowSeconds: NOW });

  it("accepts a well-formed token signed by a known key", async () => {
    const claims = await verifyAppleIdentityToken(await makeToken(validPayload()), options());
    expect(claims?.sub).toBe("001234.abcdef.5678");
    expect(claims?.email).toBe("hidden@privaterelay.appleid.com");
    expect(claims?.emailVerified).toBe(true);
    expect(claims?.isPrivateEmail).toBe(true);
  });

  it("rejects a wrong audience", async () => {
    expect(await verifyAppleIdentityToken(await makeToken({ ...validPayload(), aud: "com.example.other" }), options())).toBeNull();
  });

  it("rejects a wrong issuer", async () => {
    expect(await verifyAppleIdentityToken(await makeToken({ ...validPayload(), iss: "https://evil.example" }), options())).toBeNull();
  });

  it("rejects an expired token", async () => {
    expect(await verifyAppleIdentityToken(await makeToken({ ...validPayload(), exp: NOW - 3600 }), options())).toBeNull();
  });

  it("rejects an unknown kid", async () => {
    const token = await makeToken(validPayload(), { alg: "RS256", kid: "other" });
    expect(await verifyAppleIdentityToken(token, options())).toBeNull();
  });

  it("rejects a token signed by a different key", async () => {
    const other = await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    );
    const token = await makeToken(validPayload(), { alg: "RS256", kid: "test-kid" }, other.privateKey);
    expect(await verifyAppleIdentityToken(token, options())).toBeNull();
  });

  it("rejects HS256 tokens pretending to be Apple's", async () => {
    const h = base64UrlEncode(JSON.stringify({ alg: "HS256", kid: "test-kid" }));
    const p = base64UrlEncode(JSON.stringify(validPayload()));
    expect(await verifyAppleIdentityToken(`${h}.${p}.AAAA`, options())).toBeNull();
  });
});
