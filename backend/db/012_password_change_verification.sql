-- Separate password recovery codes from authenticated password-change codes.
ALTER TABLE password_reset_codes
  ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'reset';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'password_reset_codes_purpose_check'
      AND conrelid = 'password_reset_codes'::regclass
  ) THEN
    ALTER TABLE password_reset_codes
      ADD CONSTRAINT password_reset_codes_purpose_check
      CHECK (purpose IN ('reset', 'change'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS password_reset_active_purpose_idx
  ON password_reset_codes (user_id, purpose, created_at DESC)
  WHERE consumed_at IS NULL;
