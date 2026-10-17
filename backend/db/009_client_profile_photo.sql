ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS profile_photo bytea,
  ADD COLUMN IF NOT EXISTS profile_photo_mime text;

ALTER TABLE client_profiles
  DROP CONSTRAINT IF EXISTS client_profile_photo_mime_check;
ALTER TABLE client_profiles
  ADD CONSTRAINT client_profile_photo_mime_check
  CHECK (profile_photo_mime IS NULL OR profile_photo_mime IN ('image/jpeg', 'image/png'));
ALTER TABLE client_profiles
  DROP CONSTRAINT IF EXISTS client_profile_photo_pair_check;
ALTER TABLE client_profiles
  ADD CONSTRAINT client_profile_photo_pair_check
  CHECK ((profile_photo IS NULL) = (profile_photo_mime IS NULL));
