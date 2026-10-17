CREATE TABLE IF NOT EXISTS workout_exercise_completions (
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phase_id uuid NOT NULL REFERENCES routine_phases(id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES routine_exercises(id) ON DELETE CASCADE,
  workout_date date NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (client_id, phase_id, exercise_id, workout_date)
);

CREATE INDEX IF NOT EXISTS workout_exercise_completions_client_date_idx
  ON workout_exercise_completions (client_id, workout_date DESC);
