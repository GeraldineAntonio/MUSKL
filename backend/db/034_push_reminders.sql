ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS push_reminders_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS user_push_tokens (
  token text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK (platform IN ('android', 'ios')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_push_tokens_user_idx
  ON user_push_tokens (user_id);

CREATE TABLE IF NOT EXISTS push_reminder_deliveries (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, local_date)
);
