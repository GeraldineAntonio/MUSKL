ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS registration_email_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);

CREATE INDEX IF NOT EXISTS registration_email_codes_active_idx
  ON registration_email_codes (user_id, created_at DESC)
  WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS registration_email_codes_cleanup_idx
  ON registration_email_codes (created_at);
