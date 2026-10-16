-- Once a client deletion request has been approved and its 90-day recovery
-- window expires, remove the account and personal activity data while keeping
-- the administrative request and audit history without a user link.

ALTER TABLE memberships
  DROP CONSTRAINT IF EXISTS memberships_client_id_fkey;
ALTER TABLE memberships
  DROP CONSTRAINT IF EXISTS memberships_client_id_purge_fk;
ALTER TABLE memberships
  ADD CONSTRAINT memberships_client_id_purge_fk
  FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE memberships
  DROP CONSTRAINT IF EXISTS memberships_registered_by_fkey;
ALTER TABLE memberships
  DROP CONSTRAINT IF EXISTS memberships_registered_by_purge_fk;
ALTER TABLE memberships
  ADD CONSTRAINT memberships_registered_by_purge_fk
  FOREIGN KEY (registered_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE trainer_client_assignments
  DROP CONSTRAINT IF EXISTS trainer_client_assignments_client_id_fkey;
ALTER TABLE trainer_client_assignments
  DROP CONSTRAINT IF EXISTS trainer_client_assignments_client_purge_fk;
ALTER TABLE trainer_client_assignments
  ADD CONSTRAINT trainer_client_assignments_client_purge_fk
  FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE trainer_client_assignments
  DROP CONSTRAINT IF EXISTS trainer_client_assignments_assigned_by_fkey;
ALTER TABLE trainer_client_assignments
  DROP CONSTRAINT IF EXISTS trainer_client_assignments_assigned_by_purge_fk;
ALTER TABLE trainer_client_assignments
  ADD CONSTRAINT trainer_client_assignments_assigned_by_purge_fk
  FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE client_routine_assignments
  DROP CONSTRAINT IF EXISTS client_routine_assignments_client_id_fkey;
ALTER TABLE client_routine_assignments
  DROP CONSTRAINT IF EXISTS client_routine_assignments_client_purge_fk;
ALTER TABLE client_routine_assignments
  ADD CONSTRAINT client_routine_assignments_client_purge_fk
  FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE client_routine_assignments
  DROP CONSTRAINT IF EXISTS client_routine_assignments_assigned_by_fkey;
ALTER TABLE client_routine_assignments
  DROP CONSTRAINT IF EXISTS client_routine_assignments_assigned_by_purge_fk;
ALTER TABLE client_routine_assignments
  ALTER COLUMN assigned_by DROP NOT NULL;
ALTER TABLE client_routine_assignments
  ADD CONSTRAINT client_routine_assignments_assigned_by_purge_fk
  FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_client_id_fkey;
ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_client_purge_fk;
ALTER TABLE attendance
  ADD CONSTRAINT attendance_client_purge_fk
  FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_checked_in_by_fkey;
ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_checked_in_by_purge_fk;
ALTER TABLE attendance
  ADD CONSTRAINT attendance_checked_in_by_purge_fk
  FOREIGN KEY (checked_in_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS users_deactivated_by_fkey;
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS users_deactivated_by_purge_fk;
ALTER TABLE users
  ADD CONSTRAINT users_deactivated_by_purge_fk
  FOREIGN KEY (deactivated_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS users_rejected_by_fkey;
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS users_rejected_by_purge_fk;
ALTER TABLE users
  ADD CONSTRAINT users_rejected_by_purge_fk
  FOREIGN KEY (rejected_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE account_deletion_requests
  ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE account_deletion_requests
  DROP CONSTRAINT IF EXISTS account_deletion_requests_user_id_fkey;
ALTER TABLE account_deletion_requests
  DROP CONSTRAINT IF EXISTS account_deletion_requests_user_purge_fk;
ALTER TABLE account_deletion_requests
  ADD CONSTRAINT account_deletion_requests_user_purge_fk
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE account_deletion_requests
  DROP CONSTRAINT IF EXISTS account_deletion_requests_resolved_by_fkey;
ALTER TABLE account_deletion_requests
  DROP CONSTRAINT IF EXISTS account_deletion_requests_resolved_by_purge_fk;
ALTER TABLE account_deletion_requests
  ADD CONSTRAINT account_deletion_requests_resolved_by_purge_fk
  FOREIGN KEY (resolved_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE account_audit_events
  DROP CONSTRAINT IF EXISTS account_audit_events_actor_id_fkey;
ALTER TABLE account_audit_events
  DROP CONSTRAINT IF EXISTS account_audit_events_actor_purge_fk;
ALTER TABLE account_audit_events
  ADD CONSTRAINT account_audit_events_actor_purge_fk
  FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE account_audit_events
  DROP CONSTRAINT IF EXISTS account_audit_events_subject_id_fkey;
ALTER TABLE account_audit_events
  DROP CONSTRAINT IF EXISTS account_audit_events_subject_purge_fk;
ALTER TABLE account_audit_events
  ADD CONSTRAINT account_audit_events_subject_purge_fk
  FOREIGN KEY (subject_id) REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS users_expired_client_deactivation_idx
  ON users (reactivation_until)
  WHERE role = 'client' AND status = 'deactivated';
CREATE INDEX IF NOT EXISTS account_deletion_approved_user_idx
  ON account_deletion_requests (user_id, resolved_at)
  WHERE status = 'approved';
