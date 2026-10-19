CREATE TABLE IF NOT EXISTS client_app_open_days (
  client_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (client_id, local_date)
);

CREATE INDEX IF NOT EXISTS client_app_open_days_client_date_idx
  ON client_app_open_days (client_id, local_date DESC);
