-- Clients request a trainer; the trainer must accept before an assignment exists.
CREATE TABLE IF NOT EXISTS client_trainer_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id),
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trainer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS one_pending_trainer_request_per_client_uq
  ON client_trainer_requests (client_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS trainer_pending_requests_idx
  ON client_trainer_requests (trainer_id, requested_at)
  WHERE status = 'pending';

ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS trainer_reassignment_required boolean NOT NULL DEFAULT false;
