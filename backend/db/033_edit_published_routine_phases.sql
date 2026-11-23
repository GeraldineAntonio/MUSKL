ALTER TABLE routine_exercises
    ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;

ALTER TABLE routine_exercises
    DROP CONSTRAINT IF EXISTS routine_exercises_phase_id_day_number_position_key;

CREATE UNIQUE INDEX IF NOT EXISTS routine_exercises_active_position_key
    ON routine_exercises (phase_id, day_number, position)
    WHERE active;
