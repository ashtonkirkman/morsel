/**
 * Generic per-user document sync. Every collection (log entries, favorites, settings, body
 * scans, ...) is a bag of `{ id, json, updatedAt, deleted }` documents keyed by
 * (user, collection, id). Conflicts resolve last-writer-wins on the client-supplied
 * `updatedAt`; a tombstone (`deleted: true`) is just another write and loses to a later
 * `updatedAt`, so an entry edited on device B after being deleted on device A comes back.
 *
 * The pull cursor is the server's `synced_at`, not `updatedAt`, so a document written with
 * an old client clock is still delivered to the other devices.
 */

import { errorResponse, isJsonObject, json, readJsonBody } from "./http";
import type { Env } from "./index";
import { listDocuments, upsertDocuments, type DocumentRow } from "./db";

export interface SyncDocument {
  id: string;
  /** JSON-encoded payload; tombstones carry "{}". */
  json: string;
  /** Client clock, Unix ms. */
  updatedAt: number;
  deleted: boolean;
}

export const MAX_DOCS_PER_REQUEST = 500;
export const MAX_DOC_BYTES = 64 * 1024;
const COLLECTION_NAME = /^[a-z][a-z0-9_-]{0,39}$/;

export function isValidCollectionName(name: string): boolean {
  return COLLECTION_NAME.test(name);
}

/** Last-writer-wins: accept the incoming write only when it is strictly newer. */
export function shouldAccept(existing: { updatedAt: number } | undefined, incoming: { updatedAt: number }): boolean {
  if (!existing) return true;
  return incoming.updatedAt > existing.updatedAt;
}

/** Pure merge used by tests and mirrored by the SQL upsert in db.ts. */
export function merge(existing: SyncDocument | undefined, incoming: SyncDocument): SyncDocument {
  return shouldAccept(existing, incoming) ? incoming : (existing as SyncDocument);
}

export type ParsedDocument = { ok: true; doc: SyncDocument } | { ok: false; reason: string };

/** Validate one document from a PUT body. */
export function parseIncomingDocument(value: unknown): ParsedDocument {
  if (!isJsonObject(value)) return { ok: false, reason: "document must be an object" };
  const id = value.id;
  if (typeof id !== "string" || id.length === 0 || id.length > 128) return { ok: false, reason: "id must be a 1-128 char string" };
  const updatedAt = value.updatedAt;
  if (typeof updatedAt !== "number" || !Number.isFinite(updatedAt) || updatedAt < 0) return { ok: false, reason: `${id}: updatedAt must be Unix ms` };
  const deleted = value.deleted === true;
  let jsonText: string;
  if (deleted) {
    jsonText = "{}";
  } else {
    const raw = value.json;
    if (typeof raw === "string") {
      try {
        JSON.parse(raw);
      } catch {
        return { ok: false, reason: `${id}: json must be a JSON-encoded string` };
      }
      jsonText = raw;
    } else if (isJsonObject(raw)) {
      jsonText = JSON.stringify(raw);
    } else {
      return { ok: false, reason: `${id}: json missing` };
    }
    if (jsonText.length > MAX_DOC_BYTES) return { ok: false, reason: `${id}: document exceeds ${MAX_DOC_BYTES} bytes` };
  }
  return { ok: true, doc: { id, json: jsonText, updatedAt: Math.floor(updatedAt), deleted } };
}

function rowToWire(row: DocumentRow) {
  return { id: row.doc_id, json: row.json, updatedAt: row.updated_at, deleted: row.deleted === 1 };
}

/** GET /v1/sync/:collection?since=<unix ms> */
export async function handlePull(env: Env, userId: string, collection: string, url: URL): Promise<Response> {
  if (!isValidCollectionName(collection)) return errorResponse(400, "invalid_request_error", "Bad collection name.");
  const sinceRaw = url.searchParams.get("since");
  const since = sinceRaw ? Number(sinceRaw) : 0;
  if (!Number.isFinite(since) || since < 0) return errorResponse(400, "invalid_request_error", "since must be Unix ms.");
  const serverTime = Date.now();
  // Rows written at exactly `serverTime` by a concurrent request would be skipped next time, so
  // the cursor we hand back is one ms behind "now"; clients tolerate re-receiving a document.
  const rows = await listDocuments(env.DB, userId, collection, Math.floor(since), serverTime);
  return json({ collection, documents: rows.map(rowToWire), serverTime: serverTime - 1 });
}

/** PUT /v1/sync/:collection  { documents: [{ id, json, updatedAt, deleted }] } */
export async function handlePush(env: Env, userId: string, collection: string, request: Request): Promise<Response> {
  if (!isValidCollectionName(collection)) return errorResponse(400, "invalid_request_error", "Bad collection name.");
  const body = await readJsonBody(request);
  if (body instanceof Response) return body;
  const list = body.documents;
  if (!Array.isArray(list)) return errorResponse(400, "invalid_request_error", "documents must be an array.");
  if (list.length > MAX_DOCS_PER_REQUEST) return errorResponse(413, "request_too_large", `At most ${MAX_DOCS_PER_REQUEST} documents per request.`);
  const docs: SyncDocument[] = [];
  for (const item of list) {
    const parsed = parseIncomingDocument(item);
    if (!parsed.ok) return errorResponse(400, "invalid_request_error", parsed.reason);
    docs.push(parsed.doc);
  }
  const serverTime = Date.now();
  await upsertDocuments(env.DB, userId, collection, docs, serverTime);
  return json({ collection, accepted: docs.length, serverTime: serverTime - 1 });
}
