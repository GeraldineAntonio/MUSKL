-- Keep deactivated client/trainer accounts recoverable for two calendar months,
-- then let the API's scheduled purge permanently remove their account data.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_deactivation_window;
ALTER TABLE users ADD CONSTRAINT users_deactivation_window CHECK (
  status <> 'deactivated' OR
  (deactivated_at IS NOT NULL AND reactivation_until IN (
    deactivated_at + interval '30 days',
    deactivated_at + interval '2 months',
    deactivated_at + interval '90 days'
  ))
);

CREATE OR REPLACE FUNCTION muskl_guard_account_deactivation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active_admins integer;
BEGIN
  IF OLD.status <> 'deactivated' AND NEW.status = 'deactivated' THEN
    NEW.status_before_deactivation := OLD.status;
    IF NEW.deactivated_at IS NULL THEN NEW.deactivated_at := now(); END IF;
    NEW.reactivation_until := NEW.deactivated_at + interval '2 months';
    NEW.session_version := OLD.session_version + 1;
    IF OLD.role = 'admin' THEN
      PERFORM pg_advisory_xact_lock(hashtext(OLD.gym_id::text));
      SELECT count(*) INTO active_admins FROM users
        WHERE gym_id = OLD.gym_id AND role = 'admin'
          AND status = 'active' AND id <> OLD.id;
      IF active_admins = 0 THEN
        RAISE EXCEPTION 'No se puede dar de baja al único administrador activo.'
          USING ERRCODE = '23514';
      END IF;
    ELSIF OLD.role = 'trainer' THEN
      IF EXISTS (SELECT 1 FROM trainer_client_assignments
          WHERE trainer_id = OLD.id AND ends_at IS NULL) THEN
        RAISE EXCEPTION 'Reasigna los clientes del entrenador antes de darlo de baja.'
          USING ERRCODE = '23514';
      END IF;
    END IF;
  ELSIF OLD.status = 'deactivated' AND NEW.status <> 'deactivated' THEN
    NEW.status := COALESCE(OLD.status_before_deactivation, 'active');
    NEW.status_before_deactivation := NULL;
    NEW.deactivated_at := NULL;
    NEW.deactivated_by := NULL;
    NEW.reactivation_until := NULL;
    NEW.status_reason := NULL;
    NEW.deactivation_reason := NULL;
    NEW.deactivation_note := NULL;
    NEW.session_version := OLD.session_version + 1;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Apply the new retention window consistently to accounts already deactivated.
UPDATE users
SET reactivation_until = deactivated_at + interval '2 months'
WHERE role IN ('client', 'trainer') AND status = 'deactivated'
  AND deactivated_at IS NOT NULL;
