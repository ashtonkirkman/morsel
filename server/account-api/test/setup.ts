// Node 18 does not expose WebCrypto on globalThis (Node 19+ does). Workers always do.
import { webcrypto } from "node:crypto";

if (!(globalThis as { crypto?: unknown }).crypto) {
  Object.defineProperty(globalThis, "crypto", { value: webcrypto, configurable: true });
}
