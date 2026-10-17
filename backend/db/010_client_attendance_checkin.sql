ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_source_check;

ALTER TABLE attendance
  ADD CONSTRAINT attendance_source_check
  CHECK (source IN ('staff', 'qr', 'admin', 'app'));
