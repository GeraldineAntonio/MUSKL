-- Refresh tokens are random, one-time-use secrets. Store only their hashes;
-- existing sessions must authenticate again once to receive a refresh token.
ALTER TABLE auth_sessions
  ADD COLUMN IF NOT EXISTS refresh_token_hash text,
  ADD COLUMN IF NOT EXISTS refresh_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS auth_sessions_refresh_token_hash_uq
  ON auth_sessions (refresh_token_hash)
  WHERE refresh_token_hash IS NOT NULL;
