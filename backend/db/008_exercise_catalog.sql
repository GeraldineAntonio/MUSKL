CREATE TABLE IF NOT EXISTS exercise_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  muscle_group text NOT NULL,
  equipment text NOT NULL DEFAULT 'Peso corporal',
  instructions text,
  media_url text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE routine_exercises
  ADD COLUMN IF NOT EXISTS exercise_catalog_id uuid
    REFERENCES exercise_catalog(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS media_url text;

INSERT INTO exercise_catalog (name, muscle_group, equipment) VALUES
  ('Press de banca con barra', 'Pecho', 'Barra'),
  ('Press inclinado con barra', 'Pecho', 'Barra'),
  ('Press de banca con mancuernas', 'Pecho', 'Mancuernas'),
  ('Press inclinado con mancuernas', 'Pecho', 'Mancuernas'),
  ('Aperturas con mancuernas', 'Pecho', 'Mancuernas'),
  ('Cruce de poleas', 'Pecho', 'Poleas'),
  ('Flexiones', 'Pecho', 'Peso corporal'),
  ('Press militar con barra', 'Hombros', 'Barra'),
  ('Press de hombro con mancuernas', 'Hombros', 'Mancuernas'),
  ('Elevaciones laterales', 'Hombros', 'Mancuernas'),
  ('Elevaciones frontales', 'Hombros', 'Mancuernas'),
  ('Pájaros con mancuernas', 'Hombros', 'Mancuernas'),
  ('Face pull', 'Hombros', 'Poleas'),
  ('Jalón al pecho', 'Espalda', 'Poleas'),
  ('Remo sentado en polea', 'Espalda', 'Poleas'),
  ('Remo con barra', 'Espalda', 'Barra'),
  ('Remo con mancuerna', 'Espalda', 'Mancuernas'),
  ('Peso muerto convencional', 'Espalda y piernas', 'Barra'),
  ('Peso muerto rumano', 'Piernas y glúteos', 'Barra'),
  ('Dominadas', 'Espalda', 'Peso corporal'),
  ('Pullover en polea', 'Espalda', 'Poleas'),
  ('Curl de bíceps con barra', 'Bíceps', 'Barra'),
  ('Curl alterno con mancuernas', 'Bíceps', 'Mancuernas'),
  ('Curl martillo', 'Bíceps', 'Mancuernas'),
  ('Curl de bíceps en polea', 'Bíceps', 'Poleas'),
  ('Extensión de tríceps en polea', 'Tríceps', 'Poleas'),
  ('Extensión de tríceps por encima de la cabeza', 'Tríceps', 'Mancuernas'),
  ('Press francés', 'Tríceps', 'Barra'),
  ('Sentadilla con barra', 'Piernas', 'Barra'),
  ('Sentadilla goblet', 'Piernas', 'Mancuernas'),
  ('Prensa de piernas', 'Piernas', 'Máquina'),
  ('Extensión de piernas', 'Piernas', 'Máquina'),
  ('Curl femoral', 'Piernas', 'Máquina'),
  ('Zancadas con mancuernas', 'Piernas y glúteos', 'Mancuernas'),
  ('Hip thrust', 'Glúteos', 'Barra'),
  ('Abducción de cadera', 'Glúteos', 'Máquina'),
  ('Elevación de pantorrillas de pie', 'Pantorrillas', 'Máquina'),
  ('Plancha', 'Abdomen', 'Peso corporal'),
  ('Crunch abdominal', 'Abdomen', 'Peso corporal'),
  ('Elevación de piernas', 'Abdomen', 'Peso corporal'),
  ('Pallof press', 'Abdomen', 'Poleas'),
  ('Caminata en banda', 'Cardio', 'Máquina'),
  ('Bicicleta estática', 'Cardio', 'Máquina'),
  ('Remo ergómetro', 'Cardio', 'Máquina'),
  ('Burpee', 'Cuerpo completo', 'Peso corporal')
ON CONFLICT (name) DO NOTHING;

UPDATE routine_exercises re
SET exercise_catalog_id = ec.id
FROM exercise_catalog ec
WHERE re.exercise_catalog_id IS NULL
  AND lower(re.name) = lower(ec.name);
