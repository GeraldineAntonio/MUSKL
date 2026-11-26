ALTER TABLE users
  ADD COLUMN IF NOT EXISTS push_notifications_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS push_processed_at timestamptz;

-- Existing in-app notifications must not be replayed as pushes after deployment.
UPDATE notifications SET push_processed_at = now()
WHERE push_processed_at IS NULL;

-- Clients who already opted into workout reminders have already granted push consent.
UPDATE users u
SET push_notifications_enabled = true
FROM client_profiles cp
WHERE cp.user_id = u.id
  AND cp.push_reminders_enabled
  AND NOT u.push_notifications_enabled;

CREATE INDEX IF NOT EXISTS notifications_push_pending_idx
  ON notifications (created_at, id)
  WHERE push_processed_at IS NULL;
