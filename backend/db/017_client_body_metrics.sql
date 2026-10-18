ALTER TABLE client_profiles
  ADD COLUMN IF NOT EXISTS weight_kg numeric(5,2),
  ADD COLUMN IF NOT EXISTS height_cm numeric(5,2);

ALTER TABLE client_profiles
  DROP CONSTRAINT IF EXISTS client_profiles_weight_kg_range,
  ADD CONSTRAINT client_profiles_weight_kg_range
    CHECK (weight_kg IS NULL OR weight_kg BETWEEN 20 AND 350),
  DROP CONSTRAINT IF EXISTS client_profiles_height_cm_range,
  ADD CONSTRAINT client_profiles_height_cm_range
    CHECK (height_cm IS NULL OR height_cm BETWEEN 100 AND 250);
