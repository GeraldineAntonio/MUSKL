-- MUSKL initial PostgreSQL schema. All timestamps are stored as timestamptz.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE muskl_role AS ENUM ('client', 'trainer', 'admin');
CREATE TYPE account_status AS ENUM (
  'active_no_onboarding', 'active', 'pending', 'rejected', 'deactivated'
);
CREATE TYPE membership_status AS ENUM ('active', 'expired', 'cancelled');
CREATE TYPE routine_phase_status AS ENUM ('draft', 'published', 'pending');
CREATE TYPE request_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');

CREATE TABLE gyms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text,
  address text,
  opening_hours jsonb NOT NULL DEFAULT '{}'::jsonb,
  timezone text NOT NULL DEFAULT 'America/Mexico_City',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- A single installation starts with the gym shell. The admin can edit its details.
INSERT INTO gyms (id, name) VALUES
  ('00000000-0000-4000-8000-000000000001', 'MUSKL Gym')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  role muskl_role NOT NULL,
  status account_status NOT NULL,
  status_before_deactivation account_status,
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NOT NULL,
  phone text,
  member_number text,
  password_hash text NOT NULL,
  status_reason text,
  deactivation_reason text,
  deactivation_note text,
  deactivated_at timestamptz,
  deactivated_by uuid REFERENCES users(id),
  reactivation_until timestamptz,
  rejected_at timestamptz,
  rejected_by uuid REFERENCES users(id),
  session_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_lowercase_email CHECK (email = lower(email)),
  CONSTRAINT users_deactivation_window CHECK (
    status <> 'deactivated' OR
    (deactivated_at IS NOT NULL AND reactivation_until = deactivated_at + interval '90 days')
  ),
  CONSTRAINT users_client_member_number CHECK (role <> 'client' OR member_number IS NOT NULL)
);
CREATE UNIQUE INDEX users_email_per_gym_uq ON users (gym_id, email);
CREATE UNIQUE INDEX users_member_number_uq ON users (member_number) WHERE member_number IS NOT NULL;
CREATE INDEX users_gym_role_status_idx ON users (gym_id, role, status);

CREATE SEQUENCE member_number_seq START 1001;

CREATE TABLE membership_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  name text NOT NULL,
  price_mxn numeric(10,2),
  duration_days integer,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (gym_id, name),
  CONSTRAINT membership_duration_positive CHECK (duration_days IS NULL OR duration_days > 0),
  CONSTRAINT membership_price_nonnegative CHECK (price_mxn IS NULL OR price_mxn >= 0)
);
INSERT INTO membership_plans (gym_id, name, duration_days) VALUES
  ('00000000-0000-4000-8000-000000000001', 'Normal', 30),
  ('00000000-0000-4000-8000-000000000001', 'Estudiante', 30),
  ('00000000-0000-4000-8000-000000000001', 'Quincenal', 15),
  ('00000000-0000-4000-8000-000000000001', 'Parejas', 30),
  ('00000000-0000-4000-8000-000000000001', 'Tres personas', 30)
ON CONFLICT (gym_id, name) DO NOTHING;

CREATE TABLE client_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  goal text CHECK (goal IS NULL OR goal IN ('Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza')),
  experience_level text CHECK (experience_level IS NULL OR experience_level IN ('principiante', 'intermedio', 'avanzado')),
  days_per_week smallint CHECK (days_per_week IS NULL OR days_per_week BETWEEN 3 AND 6),
  limitations text,
  onboarding_completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id),
  plan_id uuid NOT NULL REFERENCES membership_plans(id),
  status membership_status NOT NULL DEFAULT 'active',
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  registered_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT membership_dates_valid CHECK (ends_on >= starts_on)
);
CREATE INDEX memberships_client_status_idx ON memberships (client_id, status, ends_on DESC);
CREATE UNIQUE INDEX one_current_membership_per_client_uq
  ON memberships (client_id) WHERE status = 'active';

CREATE TABLE trainer_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  specialty text,
  bio text,
  notification_preferences jsonb NOT NULL DEFAULT '{"client_activity": true, "routine_expiry": true, "daily_reminder": false}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trainer_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  storage_key text NOT NULL,
  verified_at timestamptz,
  verified_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trainer_client_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES users(id),
  client_id uuid NOT NULL REFERENCES users(id),
  assigned_by uuid REFERENCES users(id),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  CONSTRAINT trainer_assignment_dates CHECK (ends_at IS NULL OR ends_at >= starts_at)
);
CREATE UNIQUE INDEX one_current_trainer_per_client_uq
  ON trainer_client_assignments (client_id) WHERE ends_at IS NULL;
CREATE INDEX trainer_assignments_trainer_active_idx
  ON trainer_client_assignments (trainer_id) WHERE ends_at IS NULL;

CREATE TABLE admin_invite_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  token_hash text NOT NULL UNIQUE,
  label text,
  created_by uuid NOT NULL REFERENCES users(id),
  expires_at timestamptz,
  revoked_at timestamptz,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE routines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  trainer_id uuid NOT NULL REFERENCES users(id),
  name text NOT NULL,
  goal text NOT NULL CHECK (goal IN ('Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza')),
  days_per_week smallint NOT NULL CHECK (days_per_week BETWEEN 3 AND 6),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE routine_phases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id uuid NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  phase_number integer NOT NULL CHECK (phase_number > 0),
  name text NOT NULL,
  duration_weeks smallint NOT NULL DEFAULT 8 CHECK (duration_weeks = 8),
  status routine_phase_status NOT NULL DEFAULT 'draft',
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (routine_id, phase_number),
  CONSTRAINT published_phase_has_date CHECK (status <> 'published' OR published_at IS NOT NULL)
);

CREATE TABLE routine_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phase_id uuid NOT NULL REFERENCES routine_phases(id) ON DELETE CASCADE,
  day_number smallint NOT NULL CHECK (day_number BETWEEN 1 AND 7),
  position smallint NOT NULL CHECK (position > 0),
  name text NOT NULL,
  sets smallint NOT NULL CHECK (sets > 0),
  reps text NOT NULL,
  rest_seconds integer NOT NULL DEFAULT 60 CHECK (rest_seconds >= 0),
  instructions text,
  media_key text,
  UNIQUE (phase_id, day_number, position)
);

CREATE TABLE client_routine_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id),
  routine_id uuid NOT NULL REFERENCES routines(id),
  current_phase_id uuid NOT NULL REFERENCES routine_phases(id),
  phase_started_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  assigned_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT client_routine_dates CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE UNIQUE INDEX one_active_routine_per_client_uq
  ON client_routine_assignments (client_id) WHERE ended_at IS NULL;

CREATE TABLE attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  client_id uuid NOT NULL REFERENCES users(id),
  local_date date NOT NULL,
  checked_in_at timestamptz NOT NULL DEFAULT now(),
  checked_in_by uuid REFERENCES users(id),
  source text NOT NULL DEFAULT 'staff' CHECK (source IN ('staff', 'qr', 'admin')),
  UNIQUE (client_id, local_date)
);
CREATE INDEX attendance_gym_date_idx ON attendance (gym_id, checked_in_at DESC);

CREATE TABLE workout_completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phase_id uuid NOT NULL REFERENCES routine_phases(id),
  workout_date date NOT NULL,
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds > 0),
  completed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_id, phase_id, workout_date)
);
CREATE INDEX workout_completions_client_date_idx ON workout_completions (client_id, workout_date DESC);

CREATE TABLE password_reset_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose text NOT NULL DEFAULT 'reset' CHECK (purpose IN ('reset', 'change')),
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempts smallint NOT NULL DEFAULT 0,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX password_reset_user_created_idx ON password_reset_codes (user_id, created_at DESC);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_version integer NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id, expires_at);

CREATE TABLE account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  status request_status NOT NULL DEFAULT 'pending',
  requested_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES users(id),
  note text
);

CREATE TABLE account_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  actor_id uuid REFERENCES users(id),
  subject_id uuid REFERENCES users(id),
  event_type text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX account_audit_subject_idx ON account_audit_events (subject_id, created_at DESC);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enforce the two account-safety rules even if a future API path forgets them.
CREATE FUNCTION muskl_guard_account_deactivation() RETURNS trigger LANGUAGE plpgsql AS $$
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
CREATE TRIGGER users_deactivation_guard
  BEFORE UPDATE OF status ON users
  FOR EACH ROW EXECUTE FUNCTION muskl_guard_account_deactivation();
