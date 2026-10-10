import { describe, expect, it } from "vitest";
import { pkceMatches } from "../src/auth/oauth";

// RFC 7636 appendix B vectors.
const VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const CHALLENGE = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

describe("PKCE", () => {
  it("accepts the RFC vector", async () => {
    expect(await pkceMatches(VERIFIER, CHALLENGE)).toBe(true);
  });

  it("rejects a different verifier", async () => {
    expect(await pkceMatches(VERIFIER.slice(0, -1) + "l", CHALLENGE)).toBe(false);
  });

  it("rejects verifiers outside 43..128 unreserved chars", async () => {
    expect(await pkceMatches("short", CHALLENGE)).toBe(false);
    expect(await pkceMatches(VERIFIER + "!", CHALLENGE)).toBe(false);
  });
});
