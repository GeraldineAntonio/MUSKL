ALTER TABLE membership_plans
  ADD COLUMN IF NOT EXISTS min_group_size integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_group_size integer NOT NULL DEFAULT 1;

ALTER TABLE membership_plans
  DROP CONSTRAINT IF EXISTS membership_plans_group_size_check;
ALTER TABLE membership_plans
  ADD CONSTRAINT membership_plans_group_size_check
    CHECK (min_group_size >= 1 AND max_group_size >= min_group_size);

UPDATE membership_plans SET min_group_size = 2, max_group_size = 2
  WHERE name = 'Parejas';
UPDATE membership_plans SET min_group_size = 3, max_group_size = 3
  WHERE name = 'Tres personas';
INSERT INTO membership_plans (gym_id, name, duration_days, min_group_size, max_group_size)
VALUES ('00000000-0000-4000-8000-000000000001', 'Cuatro o más', 30, 4, 50)
ON CONFLICT (gym_id, name) DO UPDATE SET
  min_group_size = EXCLUDED.min_group_size,
  max_group_size = EXCLUDED.max_group_size;

DROP INDEX IF EXISTS users_member_number_uq;
CREATE INDEX IF NOT EXISTS users_member_number_idx ON users (gym_id, member_number)
  WHERE member_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS client_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  member_number text NOT NULL UNIQUE,
  plan_id uuid REFERENCES membership_plans(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS client_group_members (
  group_id uuid NOT NULL REFERENCES client_groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  is_primary boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS one_primary_per_client_group_uq
  ON client_group_members (group_id) WHERE is_primary;

INSERT INTO client_groups (gym_id, member_number)
SELECT gym_id, member_number FROM users
WHERE role = 'client' AND member_number IS NOT NULL
ON CONFLICT (member_number) DO NOTHING;

INSERT INTO client_group_members (group_id, user_id, is_primary)
SELECT g.id, u.id, true FROM users u
JOIN client_groups g ON g.member_number = u.member_number
WHERE u.role = 'client'
ON CONFLICT (user_id) DO NOTHING;
