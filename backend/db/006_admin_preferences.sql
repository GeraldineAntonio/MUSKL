ALTER TABLE users
  ADD COLUMN IF NOT EXISTS admin_notification_preferences jsonb NOT NULL
  DEFAULT '{"new_requests": true}'::jsonb;
