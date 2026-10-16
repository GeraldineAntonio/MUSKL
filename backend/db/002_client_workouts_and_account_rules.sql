-- Upgrade existing databases created before client workout tracking and the
-- expanded account deactivation metadata. Safe to reapply.
ALTER TABLE users ADD COLUMN IF NOT EXISTS status_before_deactivation account_status;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivation_reason text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivation_note text;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS opening_hours jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS workout_completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phase_id uuid NOT NULL REFERENCES routine_phases(id),
  workout_date date NOT NULL,
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds > 0),
  completed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_id, phase_id, workout_date)
);
CREATE INDEX IF NOT EXISTS workout_completions_client_date_idx
  ON workout_completions (client_id, workout_date DESC);

CREATE OR REPLACE FUNCTION muskl_guard_account_deactivation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active_admins integer;
BEGIN
  IF OLD.status <> 'deactivated' AND NEW.status = 'deactivated' THEN
    NEW.status_before_deactivation := OLD.status;
    IF NEW.deactivated_at IS NULL THEN NEW.deactivated_at := now(); END IF;
    NEW.reactivation_until := NEW.deactivated_at + interval '90 days';
    NEW.session_version := OLD.session_version + 1;
    IF OLD.role = 'admin' THEN
      PERFORM pg_advisory_xact_lock(hashtext(OLD.gym_id::text));
      SELECT count(*) INTO active_admins FROM users
        WHERE gym_id = OLD.gym_id AND role = 'admin' AND status = 'active' AND id <> OLD.id;
      IF active_admins = 0 THEN
        RAISE EXCEPTION 'No se puede dar de baja al único administrador activo.' USING ERRCODE = '23514';
      END IF;
    ELSIF OLD.role = 'trainer' THEN
      IF EXISTS (SELECT 1 FROM trainer_client_assignments WHERE trainer_id = OLD.id AND ends_at IS NULL) THEN
        RAISE EXCEPTION 'Reasigna los clientes del entrenador antes de darlo de baja.' USING ERRCODE = '23514';
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
