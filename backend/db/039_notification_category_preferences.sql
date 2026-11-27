ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb NOT NULL
  DEFAULT '{"routine_updates": true, "account_updates": true}'::jsonb;

UPDATE client_profiles
SET notification_preferences =
  '{"routine_updates": true, "account_updates": true}'::jsonb ||
  COALESCE(notification_preferences, '{}'::jsonb)
WHERE notification_preferences IS NULL
   OR NOT (notification_preferences ? 'routine_updates')
   OR NOT (notification_preferences ? 'account_updates');

UPDATE users
SET admin_notification_preferences =
  COALESCE(admin_notification_preferences, '{}'::jsonb) ||
  jsonb_build_object(
    'account_deletions',
    COALESCE((admin_notification_preferences->>'account_deletions')::boolean, true)
  )
WHERE role = 'admin';
