-- Registry rows let active gym members create app accounts without having
-- credentials or app users pre-created. A group number may identify multiple
-- people (for example, a couple), so identity is scoped by name and birth date.
CREATE TABLE IF NOT EXISTS client_member_registry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  member_number text NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  birth_date date NOT NULL,
  phone text,
  payment_due_on date,
  linked_user_id uuid UNIQUE REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT client_member_registry_number_nonempty CHECK (length(trim(member_number)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS client_member_registry_identity_uq
  ON client_member_registry (
    gym_id,
    lower(trim(regexp_replace(first_name, '[[:space:]]+', ' ', 'g'))),
    lower(trim(regexp_replace(last_name, '[[:space:]]+', ' ', 'g'))),
    birth_date
  );
CREATE INDEX IF NOT EXISTS client_member_registry_number_idx
  ON client_member_registry (gym_id, upper(trim(member_number)));

ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS member_registry_id uuid
    REFERENCES client_member_registry(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS client_profiles_member_registry_uq
  ON client_profiles (member_registry_id)
  WHERE member_registry_id IS NOT NULL;

-- Existing app accounts become registry entries too. Their current membership
-- end date is the best available due date; administrators can later correct it.
INSERT INTO client_member_registry
  (gym_id, member_number, first_name, last_name, birth_date, phone, payment_due_on, linked_user_id)
SELECT u.gym_id, u.member_number, u.first_name, u.last_name, cp.birth_date, u.phone,
       m.ends_on, u.id
FROM users u
JOIN client_profiles cp ON cp.user_id = u.id
LEFT JOIN LATERAL (
  SELECT ends_on FROM memberships
  WHERE client_id = u.id AND status = 'active'
  ORDER BY ends_on DESC LIMIT 1
) m ON true
WHERE u.role = 'client' AND u.member_number IS NOT NULL AND cp.birth_date IS NOT NULL
ON CONFLICT DO NOTHING;

UPDATE client_profiles cp
SET member_registry_id = registry.id
FROM users u
JOIN client_member_registry registry ON registry.linked_user_id = u.id
WHERE cp.user_id = u.id AND cp.member_registry_id IS NULL;
