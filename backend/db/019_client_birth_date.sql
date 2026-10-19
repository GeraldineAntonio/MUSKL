ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS birth_date date;
