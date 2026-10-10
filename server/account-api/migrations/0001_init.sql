-- Free Track account API schema. All timestamps are Unix milliseconds (INTEGER).
-- Apply with: npx wrangler d1 migrations apply freetrack --remote   (or --local)

CREATE TABLE IF NOT EXISTS users (
  id           TEXT PRIMARY KEY,
  created_at   INTEGER NOT NULL,
  display_name TEXT,
  email        TEXT,
  avatar_url   TEXT
);

-- One row per (provider, provider account). A user may link several providers.
CREATE TABLE IF NOT EXISTS identities (
  provider         TEXT NOT NULL,              -- 'apple' | 'google' | 'facebook'
  provider_user_id TEXT NOT NULL,
  user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email            TEXT,
  raw_profile_json TEXT,
  created_at       INTEGER NOT NULL,
  PRIMARY KEY (provider, provider_user_id)
);
CREATE INDEX IF NOT EXISTS identities_user_id ON identities(user_id);

-- Refresh-token sessions. The refresh token itself is never stored, only its SHA-256.
CREATE TABLE IF NOT EXISTS sessions (
  id                 TEXT PRIMARY KEY,
  user_id            TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  created_at         INTEGER NOT NULL,
  expires_at         INTEGER NOT NULL,
  revoked_at         INTEGER
);
CREATE INDEX IF NOT EXISTS sessions_user_id ON sessions(user_id);

-- One-time codes handed to the app at the end of the Google / Facebook web flow
-- (freetrack://auth/callback?code=...). Exchanged once, with PKCE, for session tokens.
CREATE TABLE IF NOT EXISTS auth_codes (
  code_hash      TEXT PRIMARY KEY,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_challenge TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL
);

-- Generic per-user JSON document store: any Codable collection syncs through here.
--   updated_at : client clock, drives last-writer-wins
--   synced_at  : server clock when the row last changed, drives the ?since= cursor
--   deleted    : 1 = tombstone (json kept as '{}')
CREATE TABLE IF NOT EXISTS documents (
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  collection TEXT NOT NULL,
  doc_id     TEXT NOT NULL,
  json       TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  synced_at  INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, collection, doc_id)
);
CREATE INDEX IF NOT EXISTS documents_cursor ON documents(user_id, collection, synced_at);
