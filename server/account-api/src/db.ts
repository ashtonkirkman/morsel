/** Typed D1 access. Every function takes the binding so tests can pass a fake. */

import type { SyncDocument } from "./sync";

export interface UserRow {
  id: string;
  created_at: number;
  display_name: string | null;
  email: string | null;
  avatar_url: string | null;
}

export interface IdentityRow {
  provider: string;
  provider_user_id: string;
  user_id: string;
  email: string | null;
  raw_profile_json: string | null;
  created_at: number;
}

export interface SessionRow {
  id: string;
  user_id: string;
  refresh_token_hash: string;
  created_at: number;
  expires_at: number;
  revoked_at: number | null;
}

export interface AuthCodeRow {
  code_hash: string;
  user_id: string;
  code_challenge: string;
  created_at: number;
  expires_at: number;
}

export interface DocumentRow {
  user_id: string;
  collection: string;
  doc_id: string;
  json: string;
  updated_at: number;
  synced_at: number;
  deleted: number;
}

/** What a provider adapter returns after a successful sign-in. */
export interface ProviderProfile {
  providerUserId: string;
  email?: string;
  emailVerified?: boolean;
  name?: string;
  avatarUrl?: string;
  raw: unknown;
}

export async function getUser(db: D1Database, id: string): Promise<UserRow | null> {
  return db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();
}

export async function listProviders(db: D1Database, userId: string): Promise<string[]> {
  const res = await db.prepare("SELECT provider FROM identities WHERE user_id = ? ORDER BY created_at").bind(userId).all<{ provider: string }>();
  return (res.results ?? []).map((r) => r.provider);
}

/**
 * Find-or-create the user behind a provider identity. Existing users keep their display name /
 * email unless those are empty (Apple only sends the name on the very first sign-in).
 */
export async function upsertIdentity(db: D1Database, provider: string, profile: ProviderProfile, now: number): Promise<UserRow> {
  const existing = await db
    .prepare("SELECT * FROM identities WHERE provider = ? AND provider_user_id = ?")
    .bind(provider, profile.providerUserId)
    .first<IdentityRow>();
  const rawJson = JSON.stringify(profile.raw ?? null).slice(0, 8192);
  if (existing) {
    const user = await getUser(db, existing.user_id);
    if (!user) throw new Error("identity without user");
    await db.batch([
      db
        .prepare("UPDATE identities SET email = COALESCE(?, email), raw_profile_json = ? WHERE provider = ? AND provider_user_id = ?")
        .bind(profile.email ?? null, rawJson, provider, profile.providerUserId),
      db
        .prepare("UPDATE users SET display_name = COALESCE(display_name, ?), email = COALESCE(email, ?), avatar_url = COALESCE(?, avatar_url) WHERE id = ?")
        .bind(profile.name ?? null, profile.email ?? null, profile.avatarUrl ?? null, user.id),
    ]);
    return (await getUser(db, user.id)) ?? user;
  }
  const userId = crypto.randomUUID();
  await db.batch([
    db
      .prepare("INSERT INTO users (id, created_at, display_name, email, avatar_url) VALUES (?, ?, ?, ?, ?)")
      .bind(userId, now, profile.name ?? null, profile.email ?? null, profile.avatarUrl ?? null),
    db
      .prepare("INSERT INTO identities (provider, provider_user_id, user_id, email, raw_profile_json, created_at) VALUES (?, ?, ?, ?, ?, ?)")
      .bind(provider, profile.providerUserId, userId, profile.email ?? null, rawJson, now),
  ]);
  const user = await getUser(db, userId);
  if (!user) throw new Error("user insert failed");
  return user;
}

export async function insertSession(db: D1Database, row: SessionRow): Promise<void> {
  await db
    .prepare("INSERT INTO sessions (id, user_id, refresh_token_hash, created_at, expires_at, revoked_at) VALUES (?, ?, ?, ?, ?, NULL)")
    .bind(row.id, row.user_id, row.refresh_token_hash, row.created_at, row.expires_at)
    .run();
}

export async function getSession(db: D1Database, id: string): Promise<SessionRow | null> {
  return db.prepare("SELECT * FROM sessions WHERE id = ?").bind(id).first<SessionRow>();
}

export async function getSessionByRefreshHash(db: D1Database, hash: string): Promise<SessionRow | null> {
  return db.prepare("SELECT * FROM sessions WHERE refresh_token_hash = ?").bind(hash).first<SessionRow>();
}

/** Rotate the refresh token in place and extend the session. */
export async function rotateSession(db: D1Database, id: string, newHash: string, expiresAt: number): Promise<void> {
  await db.prepare("UPDATE sessions SET refresh_token_hash = ?, expires_at = ? WHERE id = ?").bind(newHash, expiresAt, id).run();
}

export async function revokeSession(db: D1Database, id: string, now: number): Promise<void> {
  await db.prepare("UPDATE sessions SET revoked_at = COALESCE(revoked_at, ?) WHERE id = ?").bind(now, id).run();
}

export async function insertAuthCode(db: D1Database, row: AuthCodeRow): Promise<void> {
  await db
    .prepare("INSERT INTO auth_codes (code_hash, user_id, code_challenge, created_at, expires_at) VALUES (?, ?, ?, ?, ?)")
    .bind(row.code_hash, row.user_id, row.code_challenge, row.created_at, row.expires_at)
    .run();
}

/** Atomically fetch-and-delete a one-time code. Returns null when unknown or already used. */
export async function consumeAuthCode(db: D1Database, codeHash: string): Promise<AuthCodeRow | null> {
  const row = await db.prepare("DELETE FROM auth_codes WHERE code_hash = ? RETURNING *").bind(codeHash).first<AuthCodeRow>();
  return row ?? null;
}

export async function deleteExpiredAuthCodes(db: D1Database, now: number): Promise<void> {
  await db.prepare("DELETE FROM auth_codes WHERE expires_at < ?").bind(now).run();
}

/** Account deletion: every row the user owns. Explicit order in case FK cascades are off. */
export async function deleteUser(db: D1Database, userId: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM documents WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM auth_codes WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM sessions WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM identities WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM users WHERE id = ?").bind(userId),
  ]);
}

/** Documents whose server write time is in (since, before]. */
export async function listDocuments(db: D1Database, userId: string, collection: string, since: number, before: number): Promise<DocumentRow[]> {
  const res = await db
    .prepare("SELECT * FROM documents WHERE user_id = ? AND collection = ? AND synced_at > ? AND synced_at <= ? ORDER BY synced_at ASC LIMIT 5000")
    .bind(userId, collection, since, before)
    .all<DocumentRow>();
  return res.results ?? [];
}

/**
 * Batch last-writer-wins upsert. The WHERE on the conflict clause is the SQL twin of
 * `shouldAccept()` in sync.ts: an older `updated_at` never overwrites a newer row.
 */
export async function upsertDocuments(db: D1Database, userId: string, collection: string, docs: SyncDocument[], syncedAt: number): Promise<void> {
  if (docs.length === 0) return;
  const stmt = db.prepare(
    `INSERT INTO documents (user_id, collection, doc_id, json, updated_at, synced_at, deleted)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, collection, doc_id) DO UPDATE SET
       json = excluded.json, updated_at = excluded.updated_at, synced_at = excluded.synced_at, deleted = excluded.deleted
     WHERE excluded.updated_at > documents.updated_at`,
  );
  const batch = docs.map((d) => stmt.bind(userId, collection, d.id, d.json, d.updatedAt, syncedAt, d.deleted ? 1 : 0));
  // D1 batches are limited in size; 100 statements per batch keeps well under it.
  for (let i = 0; i < batch.length; i += 100) {
    await db.batch(batch.slice(i, i + 100));
  }
}
