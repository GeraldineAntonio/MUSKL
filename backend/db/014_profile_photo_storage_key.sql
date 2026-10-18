ALTER TABLE users
  ADD COLUMN IF NOT EXISTS profile_photo_storage_key text,
  ADD COLUMN IF NOT EXISTS profile_photo_mime text;

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS user_profile_photo_mime_check;
ALTER TABLE users
  ADD CONSTRAINT user_profile_photo_mime_check
  CHECK (profile_photo_mime IS NULL OR profile_photo_mime IN ('image/jpeg', 'image/png'));
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS user_profile_photo_pair_check;
ALTER TABLE users
  ADD CONSTRAINT user_profile_photo_pair_check
  CHECK ((profile_photo_storage_key IS NULL) = (profile_photo_mime IS NULL));
