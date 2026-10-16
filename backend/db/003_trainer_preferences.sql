ALTER TABLE trainer_profiles
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb NOT NULL
  DEFAULT '{"client_activity": true, "routine_expiry": true, "daily_reminder": false}'::jsonb;
