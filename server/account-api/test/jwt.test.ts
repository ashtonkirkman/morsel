import { describe, expect, it } from "vitest";
import { base64UrlDecode, base64UrlEncode, decodeJwt, randomToken, safeEqual, sha256Base64Url, signHS256, verifyHS256 } from "../src/jwt";

const SECRET = "test-secret-that-is-long-enough";

describe("base64url", () => {
  it("round-trips bytes without padding", () => {
    const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
    const encoded = base64UrlEncode(bytes);
    expect(encoded).not.toMatch(/[+/=]/);
    expect([...base64UrlDecode(encoded)]).toEqual([...bytes]);
  });

  it("matches RFC 7636 appendix B for the S256 challenge", async () => {
    const challenge = await sha256Base64Url("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk");
    expect(challenge).toBe("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  });
});

describe("HS256", () => {
  it("signs and verifies", async () => {
    const now = Math.floor(Date.now() / 1000);
    const token = await signHS256({ sub: "u1", sid: "s1", typ: "access", iat: now, exp: now + 60 }, SECRET);
    expect(token.split(".")).toHaveLength(3);
    const payload = await verifyHS256(token, SECRET);
    expect(payload?.sub).toBe("u1");
    expect(payload?.sid).toBe("s1");
  });

  it("rejects a wrong secret", async () => {
    const token = await signHS256({ sub: "u1" }, SECRET);
    expect(await verifyHS256(token, SECRET + "x")).toBeNull();
  });

  it("rejects tampered payloads", async () => {
    const token = await signHS256({ sub: "u1" }, SECRET);
    const [h, , s] = token.split(".");
    const forged = `${h}.${base64UrlEncode(JSON.stringify({ sub: "admin" }))}.${s}`;
    expect(await verifyHS256(forged, SECRET)).toBeNull();
  });

  it("rejects expired tokens but allows 60 s leeway", async () => {
    const now = 1_700_000_000;
    const token = await signHS256({ sub: "u1", exp: now }, SECRET);
    expect(await verifyHS256(token, SECRET, now + 30)).not.toBeNull();
    expect(await verifyHS256(token, SECRET, now + 61)).toBeNull();
  });

  it("rejects alg=none and garbage", async () => {
    const header = base64UrlEncode(JSON.stringify({ alg: "none", typ: "JWT" }));
    const body = base64UrlEncode(JSON.stringify({ sub: "u1" }));
    expect(await verifyHS256(`${header}.${body}.`, SECRET)).toBeNull();
    expect(await verifyHS256("not-a-jwt", SECRET)).toBeNull();
    expect(decodeJwt("a.b")).toBeNull();
  });
});

describe("tokens", () => {
  it("randomToken is 43 chars of base64url and unique", () => {
    const a = randomToken();
    const b = randomToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a).not.toBe(b);
  });

  it("safeEqual compares exactly", () => {
    expect(safeEqual("abc", "abc")).toBe(true);
    expect(safeEqual("abc", "abd")).toBe(false);
    expect(safeEqual("abc", "ab")).toBe(false);
  });
});
