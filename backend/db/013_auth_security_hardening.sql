-- Persistent, account-keyed login throttling without storing raw emails or
-- member numbers, plus one-time codes for changing a signed-in user's email.
CREATE TABLE IF NOT EXISTS auth_login_limits (
  identifier_hash text PRIMARY KEY,
  attempt_count smallint NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  window_started_at timestamptz NOT NULL DEFAULT now(),
  blocked_until timestamptz
);
CREATE INDEX IF NOT EXISTS auth_login_limits_window_idx
  ON auth_login_limits (window_started_at);

CREATE TABLE IF NOT EXISTS email_change_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  new_email text NOT NULL,
  code_hash text NOT NULL,
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz,
  CONSTRAINT email_change_codes_lowercase_email CHECK (new_email = lower(new_email))
);
CREATE INDEX IF NOT EXISTS email_change_codes_user_active_idx
  ON email_change_codes (user_id, created_at DESC)
  WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS email_change_codes_cleanup_idx
  ON email_change_codes (created_at);
