-- Separate the main front and back thigh groups in the exercise catalog.
UPDATE exercise_catalog
SET muscle_group = 'Cuádriceps'
WHERE name IN (
  'Sentadilla con barra',
  'Sentadilla goblet',
  'Prensa de piernas',
  'Extensión de piernas'
);

UPDATE exercise_catalog
SET muscle_group = 'Femoral'
WHERE name = 'Curl femoral';
