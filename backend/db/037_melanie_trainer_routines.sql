-- Save the two photographed six-day programs in trainer Melanie Oc's library.
-- This migration is safe to re-run and never overwrites existing exercise work.

INSERT INTO exercise_catalog (name, muscle_group, equipment, instructions)
VALUES ('Elevación en tejedora', 'Glúteos', 'Máquina',
  'Ajusta la máquina y apoya el cuerpo con la espalda neutra. Empuja el apoyo con la pierna o la cadera según el mecanismo, contrayendo el glúteo sin girar la pelvis. Regresa despacio y repite con control.')
ON CONFLICT (name) DO UPDATE
SET instructions = COALESCE(NULLIF(exercise_catalog.instructions, ''), EXCLUDED.instructions),
    active = true;

UPDATE exercise_catalog
SET instructions = CASE name
  WHEN 'Peso muerto convencional con barra' THEN
    'Coloca los pies al ancho de cadera y la barra cerca de las espinillas. Lleva la cadera atrás, toma la barra y mantén la espalda neutra. Empuja el suelo para levantarte, manteniendo la barra cerca del cuerpo; baja con control.'
  WHEN 'Extensión de tríceps sobre cabeza con cuerda' THEN
    'De espaldas a la polea baja, sujeta la cuerda por detrás de la cabeza. Mantén los codos apuntando al frente y extiende los brazos arriba sin arquear la espalda. Flexiona los codos lentamente para regresar.'
  WHEN 'Curl de bíceps unilateral en polea baja' THEN
    'Sujeta una agarradera conectada a la polea baja y mantén el codo junto al torso. Flexiona el brazo llevando la mano al hombro, sin mover el tronco; baja despacio y cambia de lado.'
  WHEN 'Patada de tríceps con mancuerna' THEN
    'Inclina el torso con la espalda neutra y mantén el codo pegado al cuerpo. Extiende el antebrazo hacia atrás hasta estirar el brazo, sin mover el hombro. Regresa lentamente y completa el otro lado.'
  WHEN 'Elevación en tejedora' THEN
    'Ajusta la máquina y apoya el cuerpo con la espalda neutra. Empuja el apoyo con la pierna o la cadera según el mecanismo, contrayendo el glúteo sin girar la pelvis. Regresa despacio y repite con control.'
  ELSE instructions
END
WHERE name IN (
  'Peso muerto convencional con barra',
  'Extensión de tríceps sobre cabeza con cuerda',
  'Curl de bíceps unilateral en polea baja',
  'Patada de tríceps con mancuerna',
  'Elevación en tejedora'
) AND (instructions IS NULL OR btrim(instructions) = '');

CREATE TEMP TABLE _melanie_programs (
  routine_number smallint PRIMARY KEY,
  routine_name text NOT NULL
) ON COMMIT DROP;

INSERT INTO _melanie_programs VALUES
  (1, 'Rutina 1 FEM · Volumen tren inferior'),
  (2, 'Rutina 2 FEM · Volumen tren inferior');

CREATE TEMP TABLE _melanie_exercises (
  routine_number smallint NOT NULL,
  day_number smallint NOT NULL,
  position smallint NOT NULL,
  exercise_name text NOT NULL,
  sets smallint NOT NULL,
  reps text NOT NULL,
  rest_seconds integer NOT NULL
) ON COMMIT DROP;

INSERT INTO _melanie_exercises VALUES
  (1,1,1,'Sentadilla hack',4,'10',120),
  (1,1,2,'Hip thrust',4,'10',120),
  (1,1,3,'Peso muerto convencional con barra',4,'10',120),
  (1,1,4,'Curl femoral sentado',4,'10',120),
  (1,1,5,'Aducción de cadera en máquina',4,'10',120),
  (1,1,6,'Elevación de pantorrillas en máquina',4,'10',120),
  (1,2,1,'Jalón al pecho',3,'15',60),
  (1,2,2,'Face pull en polea',3,'15',60),
  (1,2,3,'Curl de bíceps doble en polea baja',3,'15',60),
  (1,2,4,'Curl alterno de bíceps de pie con mancuernas',3,'15',60),
  (1,2,5,'Elevación lateral con mancuernas',3,'15',60),
  (1,2,6,'Press militar con mancuernas',3,'15',60),
  (1,3,1,'Press de banca con barra',3,'15',60),
  (1,3,2,'Cristo en máquina (peck deck)',3,'15',60),
  (1,3,3,'Aperturas de pecho en polea baja',3,'15',60),
  (1,3,4,'Extensión de tríceps con cuerda',3,'15',60),
  (1,3,5,'Extensión de tríceps con barra recta en polea',3,'15',60),
  (1,3,6,'Extensión de tríceps sobre cabeza con cuerda',3,'15',60),
  (1,3,7,'Fondos en paralelas',3,'15',60),
  (1,4,1,'Desplante con mancuernas',4,'10',120),
  (1,4,2,'Sentadilla hack',4,'10',120),
  (1,4,3,'Extensión de piernas en máquina',4,'10',120),
  (1,4,4,'Prensa a 45 grados',4,'10',120),
  (1,4,5,'Aducción de cadera en máquina',4,'10',120),
  (1,5,1,'Jalón al pecho',3,'15',60),
  (1,5,2,'Face pull en polea',3,'15',60),
  (1,5,3,'Curl de bíceps doble en polea baja',3,'15',60),
  (1,5,4,'Curl alterno de bíceps de pie con mancuernas',3,'15',60),
  (1,5,5,'Elevación lateral con mancuernas',3,'15',60),
  (1,5,6,'Press militar con mancuernas',3,'15',60),
  (1,6,1,'Press de banca con barra',3,'15',60),
  (1,6,2,'Cristo en máquina (peck deck)',3,'15',60),
  (1,6,3,'Aperturas de pecho en polea baja',3,'15',60),
  (1,6,4,'Extensión de tríceps con cuerda',3,'15',60),
  (1,6,5,'Extensión de tríceps con barra recta en polea',3,'15',60),
  (1,6,6,'Extensión de tríceps sobre cabeza con cuerda',3,'15',60),
  (1,6,7,'Fondos en paralelas',3,'15',60),
  (2,1,1,'Sentadilla búlgara con mancuernas',4,'8',90),
  (2,1,2,'Sentadilla hack',4,'8',90),
  (2,1,3,'Extensión de piernas en máquina',4,'8',90),
  (2,1,4,'Peso muerto rumano con mancuernas',4,'8',90),
  (2,1,5,'Patada de glúteo en polea',4,'8',90),
  (2,1,6,'Curl de bíceps en máquina',4,'8',90),
  (2,1,7,'Aducción de cadera en máquina',4,'8',90),
  (2,1,8,'Elevación en tejedora',4,'8',90),
  (2,2,1,'Cristo en máquina (peck deck)',3,'20',60),
  (2,2,2,'Press inclinado con mancuernas',3,'20',60),
  (2,2,3,'Patada de tríceps con mancuerna',3,'20',60),
  (2,2,4,'Press francés con barra Z',3,'20',60),
  (2,2,5,'Press California con barra',3,'20',60),
  (2,3,1,'Sentadilla búlgara con mancuernas',4,'8',90),
  (2,3,2,'Sentadilla hack',4,'8',90),
  (2,3,3,'Extensión de piernas en máquina',4,'8',90),
  (2,3,4,'Peso muerto rumano con mancuernas',4,'8',90),
  (2,3,5,'Patada de glúteo en polea',4,'8',90),
  (2,3,6,'Curl de bíceps en máquina',4,'8',90),
  (2,3,7,'Aducción de cadera en máquina',4,'8',90),
  (2,3,8,'Elevación en tejedora',4,'8',90),
  (2,4,1,'Jalón al pecho con agarre supino',3,'20',60),
  (2,4,2,'Remo a un brazo con mancuerna',3,'20',60),
  (2,4,3,'Curl alterno de bíceps de pie con mancuernas',3,'20',60),
  (2,4,4,'Curl de bíceps unilateral en polea baja',3,'20',60),
  (2,4,5,'Press militar con mancuernas',3,'20',60),
  (2,4,6,'Elevación lateral con mancuernas',3,'20',60),
  (2,5,1,'Cristo en máquina (peck deck)',3,'20',60),
  (2,5,2,'Press inclinado con mancuernas',3,'20',60),
  (2,5,3,'Patada de tríceps con mancuerna',3,'20',60),
  (2,5,4,'Press francés con barra Z',3,'20',60),
  (2,5,5,'Press California con barra',3,'20',60),
  (2,6,1,'Jalón al pecho con agarre supino',3,'20',60),
  (2,6,2,'Remo a un brazo con mancuerna',3,'20',60),
  (2,6,3,'Curl alterno de bíceps de pie con mancuernas',3,'20',60),
  (2,6,4,'Curl de bíceps unilateral en polea baja',3,'20',60),
  (2,6,5,'Press militar con mancuernas',3,'20',60),
  (2,6,6,'Elevación lateral con mancuernas',3,'20',60);

DO $migration$
DECLARE
  v_trainer_id uuid;
  v_gym_id uuid;
  v_routine_id uuid;
  v_phase_id uuid;
  v_program record;
  v_expected integer;
  v_existing integer;
  v_inserted integer;
  v_missing text;
BEGIN
  SELECT u.id, u.gym_id INTO v_trainer_id, v_gym_id
  FROM users u
  WHERE u.role = 'trainer'
    AND lower(u.first_name) = 'melanie'
    AND lower(u.last_name) = 'oc'
    AND u.status = 'active'
  ORDER BY u.created_at
  LIMIT 1;

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró la cuenta activa de entrenadora Melanie Oc.';
  END IF;

  FOR v_program IN SELECT routine_number, routine_name FROM _melanie_programs ORDER BY routine_number
  LOOP
    SELECT r.id INTO v_routine_id
    FROM routines r
    WHERE r.trainer_id = v_trainer_id
      AND r.name = v_program.routine_name
      AND r.active
    ORDER BY r.created_at
    LIMIT 1;

    IF v_routine_id IS NULL THEN
      INSERT INTO routines (gym_id, trainer_id, name, goal, days_per_week)
      VALUES (v_gym_id, v_trainer_id, v_program.routine_name, 'Masa muscular', 6)
      RETURNING id INTO v_routine_id;
    END IF;

    SELECT rp.id INTO v_phase_id
    FROM routine_phases rp
    WHERE rp.routine_id = v_routine_id AND rp.phase_number = 1
    LIMIT 1;

    IF v_phase_id IS NULL THEN
      INSERT INTO routine_phases
        (routine_id, phase_number, name, duration_weeks, status, published_at)
      VALUES (v_routine_id, 1, 'Fase 1', 8, 'published', now())
      RETURNING id INTO v_phase_id;
    END IF;

    SELECT count(*) INTO v_expected FROM _melanie_exercises
    WHERE routine_number = v_program.routine_number;

    SELECT string_agg(missing.exercise_name, ', ')
      INTO v_missing
    FROM (
      SELECT DISTINCT seed.exercise_name
      FROM _melanie_exercises seed
      LEFT JOIN exercise_catalog ec
        ON ec.name = seed.exercise_name AND ec.active
      WHERE seed.routine_number = v_program.routine_number AND ec.id IS NULL
    ) AS missing;

    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'Faltan ejercicios activos del catálogo: %', v_missing;
    END IF;

    SELECT count(*) INTO v_existing
    FROM routine_exercises re
    WHERE re.phase_id = v_phase_id AND re.active;

    IF v_existing = 0 THEN
      INSERT INTO routine_exercises
        (phase_id, day_number, position, exercise_catalog_id, name,
         sets, reps, rest_seconds, media_url, instructions)
      SELECT v_phase_id, seed.day_number, seed.position, ec.id, ec.name,
        seed.sets, seed.reps, seed.rest_seconds, ec.media_url, ec.instructions
      FROM _melanie_exercises seed
      JOIN exercise_catalog ec ON ec.name = seed.exercise_name AND ec.active
      WHERE seed.routine_number = v_program.routine_number
      ORDER BY seed.day_number, seed.position;

      GET DIAGNOSTICS v_inserted = ROW_COUNT;
      IF v_inserted <> v_expected THEN
        RAISE EXCEPTION 'La rutina % esperaba % ejercicios y cargó %.',
          v_program.routine_name, v_expected, v_inserted;
      END IF;
    ELSIF v_existing <> v_expected THEN
      RAISE EXCEPTION 'La rutina % ya tiene % ejercicios; se esperaban %.',
        v_program.routine_name, v_existing, v_expected;
    END IF;

    UPDATE routine_phases
    SET status = 'published', published_at = COALESCE(published_at, now())
    WHERE id = v_phase_id;

    INSERT INTO account_audit_events (gym_id, actor_id, event_type, details)
    SELECT v_gym_id, v_trainer_id, 'routine_seeded_from_spreadsheet',
      jsonb_build_object('routine_id', v_routine_id, 'phase_id', v_phase_id,
                         'name', v_program.routine_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM account_audit_events a
      WHERE a.actor_id = v_trainer_id
        AND a.event_type = 'routine_seeded_from_spreadsheet'
        AND a.details ->> 'routine_id' = v_routine_id::text
    );
  END LOOP;
END
$migration$;
