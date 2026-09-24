-- EMMA / Metropolis – Postgres-Schema für alle Workflows.
-- Idempotent: kann beliebig oft ausgeführt werden, bestehende Daten bleiben erhalten.

CREATE TABLE IF NOT EXISTS interaction_memory (
  id          bigserial PRIMARY KEY,
  session_id  text,
  user_id     text,
  channel     text,
  input       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE interaction_memory ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- Jeder Lauf des EMMA_ENGINE_HUB (ersetzt die vielen *_ENGINE-Workflows).
CREATE TABLE IF NOT EXISTS engine_runs (
  id          bigserial PRIMARY KEY,
  engine      text NOT NULL,
  session_id  text,
  sender      text,
  input       text,
  output      jsonb,
  risk_level  text NOT NULL DEFAULT 'LOW',   -- LOW | MEDIUM | HIGH
  status      text NOT NULL DEFAULT 'ok',    -- ok | no_json | parse_error
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS engine_runs_created_at_idx ON engine_runs (created_at);

CREATE TABLE IF NOT EXISTS emma_tasks (
  id             bigserial PRIMARY KEY,
  title          text NOT NULL,
  source_engine  text,
  run_id         bigint REFERENCES engine_runs (id) ON DELETE SET NULL,
  status         text NOT NULL DEFAULT 'open',   -- open | done
  created_at     timestamptz NOT NULL DEFAULT now(),
  done_at        timestamptz
);

-- HIGH-Risk-Ergebnisse landen hier und warten auf Irinas Freigabe.
CREATE TABLE IF NOT EXISTS emma_approvals (
  id          bigserial PRIMARY KEY,
  run_id      bigint REFERENCES engine_runs (id) ON DELETE SET NULL,
  engine      text,
  reason      text,
  status      text NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
  created_at  timestamptz NOT NULL DEFAULT now(),
  decided_at  timestamptz
);

-- Log- und Sync-Events aus METROPOLIS_DATA_GATEWAY.
CREATE TABLE IF NOT EXISTS emma_events (
  id          bigserial PRIMARY KEY,
  source      text,
  level       text NOT NULL DEFAULT 'INFO',
  message     text,
  payload     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_leads (
  id              bigserial PRIMARY KEY,
  name            text,
  email           text,
  phone           text,
  company         text,
  status          text DEFAULT 'new',
  interest_score  int,
  context         text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE crm_leads ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS kpi_metrics (
  id           bigserial PRIMARY KEY,
  metric_name  text NOT NULL,
  value        numeric,
  unit         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workflow_registry (
  id             bigserial PRIMARY KEY,
  workflow_id    text,
  workflow_name  text,
  workflow_json  jsonb,
  purpose        text,
  created_by     text,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE workflow_registry ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS self_modification_log (
  id                 bigserial PRIMARY KEY,
  modification_type  text,
  target             text,
  after_state        jsonb,
  reasoning          text,
  created_at         timestamptz NOT NULL DEFAULT now()
);
