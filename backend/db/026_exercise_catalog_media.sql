ALTER TABLE exercise_catalog
  ADD COLUMN IF NOT EXISTS media_key text,
  ADD COLUMN IF NOT EXISTS media_mime text;
