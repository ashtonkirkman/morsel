import { describe, expect, it } from "vitest";
import { isValidCollectionName, merge, parseIncomingDocument, shouldAccept, type SyncDocument } from "../src/sync";

const doc = (id: string, updatedAt: number, deleted = false, json = '{"name":"x"}'): SyncDocument => ({ id, updatedAt, deleted, json: deleted ? "{}" : json });

describe("last-writer-wins", () => {
  it("accepts anything when nothing exists", () => {
    expect(shouldAccept(undefined, doc("a", 1))).toBe(true);
  });

  it("newer updatedAt wins, older loses, equal keeps existing", () => {
    expect(merge(doc("a", 100), doc("a", 200)).updatedAt).toBe(200);
    expect(merge(doc("a", 200), doc("a", 100)).updatedAt).toBe(200);
    const existing = doc("a", 100, false, '{"v":"existing"}');
    expect(merge(existing, doc("a", 100, false, '{"v":"incoming"}'))).toBe(existing);
  });

  it("a newer tombstone deletes, an older tombstone is ignored", () => {
    expect(merge(doc("a", 100), doc("a", 150, true)).deleted).toBe(true);
    expect(merge(doc("a", 200), doc("a", 150, true)).deleted).toBe(false);
  });

  it("an edit after a tombstone resurrects the document", () => {
    const resurrected = merge(doc("a", 150, true), doc("a", 300));
    expect(resurrected.deleted).toBe(false);
    expect(resurrected.json).toBe('{"name":"x"}');
  });
});

describe("parseIncomingDocument", () => {
  it("accepts a string json payload", () => {
    const r = parseIncomingDocument({ id: "a", json: '{"x":1}', updatedAt: 5.9 });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.doc.updatedAt).toBe(5);
      expect(r.doc.deleted).toBe(false);
    }
  });

  it("accepts an object json payload and re-encodes it", () => {
    const r = parseIncomingDocument({ id: "a", json: { x: 1 }, updatedAt: 1 });
    expect(r.ok && r.doc.json).toBe('{"x":1}');
  });

  it("tombstones need no json", () => {
    const r = parseIncomingDocument({ id: "a", deleted: true, updatedAt: 1 });
    expect(r.ok && r.doc.json).toBe("{}");
  });

  it("rejects bad ids, timestamps and malformed json", () => {
    expect(parseIncomingDocument({ json: "{}", updatedAt: 1 }).ok).toBe(false);
    expect(parseIncomingDocument({ id: "a", json: "{}", updatedAt: "x" }).ok).toBe(false);
    expect(parseIncomingDocument({ id: "a", json: "{nope", updatedAt: 1 }).ok).toBe(false);
    expect(parseIncomingDocument({ id: "a", updatedAt: 1 }).ok).toBe(false);
    expect(parseIncomingDocument("nope").ok).toBe(false);
  });

  it("rejects documents over 64 KB", () => {
    const big = JSON.stringify({ s: "x".repeat(65 * 1024) });
    expect(parseIncomingDocument({ id: "a", json: big, updatedAt: 1 }).ok).toBe(false);
  });
});

describe("collection names", () => {
  it("allows lowercase slugs only", () => {
    expect(isValidCollectionName("log-entries")).toBe(true);
    expect(isValidCollectionName("body_scans")).toBe(true);
    expect(isValidCollectionName("LogEntries")).toBe(false);
    expect(isValidCollectionName("../x")).toBe(false);
    expect(isValidCollectionName("")).toBe(false);
  });
});
