ALTER TABLE users
  ADD COLUMN IF NOT EXISTS profile_details_updated_at timestamptz;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS bio text;
