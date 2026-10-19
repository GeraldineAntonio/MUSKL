ALTER TABLE workout_completions
  ADD COLUMN IF NOT EXISTS scheduled_for_date date,
  ADD COLUMN IF NOT EXISTS scheduled_day_number smallint,
  ADD COLUMN IF NOT EXISTS is_fully_completed boolean NOT NULL DEFAULT true;

UPDATE workout_completions
SET scheduled_for_date = workout_date,
    scheduled_day_number = extract(isodow FROM workout_date)::smallint
WHERE scheduled_for_date IS NULL OR scheduled_day_number IS NULL;

ALTER TABLE workout_completions
  ALTER COLUMN scheduled_for_date SET NOT NULL,
  ALTER COLUMN scheduled_day_number SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS workout_completion_schedule_uq
  ON workout_completions (client_id, phase_id, scheduled_for_date);
