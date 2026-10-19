ALTER TABLE workout_exercise_completions
  ADD COLUMN IF NOT EXISTS sets_completed smallint NOT NULL DEFAULT 1;

-- Rows created before set tracking represented a fully completed exercise.
UPDATE workout_exercise_completions c
SET sets_completed = re.sets
FROM routine_exercises re
WHERE re.id = c.exercise_id
  AND c.sets_completed = 1
  AND re.sets > 1;
