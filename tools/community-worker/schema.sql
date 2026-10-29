-- D1 schema for the community setups Worker. Run once with:
--   npx wrangler d1 execute mmf-community --remote --file schema.sql
-- No column holds an IP address, a name, an e-mail address or any other data about the sender.

CREATE TABLE IF NOT EXISTS submissions (
  id                TEXT PRIMARY KEY,           -- random, "s_" and 32 hex digits
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'published', 'rejected', 'delete_requested')),
  bundle_id         TEXT NOT NULL,
  title             TEXT NOT NULL,
  submission        TEXT NOT NULL,              -- the checked setup as JSON, in the repository format
  delete_token_hash TEXT NOT NULL,              -- SHA-256 (hex) of the delete token; the token itself is never stored
  created_at        TEXT NOT NULL,              -- ISO 8601, UTC
  license           TEXT NOT NULL DEFAULT 'CC0-1.0'
);

CREATE INDEX IF NOT EXISTS submissions_status ON submissions (status, created_at);
