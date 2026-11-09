CREATE TABLE IF NOT EXISTS trainer_exercise_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exercise_catalog_id uuid NOT NULL REFERENCES exercise_catalog(id) ON DELETE CASCADE,
  media_key text NOT NULL,
  media_mime text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trainer_id, exercise_catalog_id)
);

CREATE INDEX IF NOT EXISTS trainer_exercise_media_exercise_idx
  ON trainer_exercise_media (exercise_catalog_id);
