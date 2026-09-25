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
ALTER TABLE interaction_memory ADD COLUMN IF NOT EXISTS output text;   -- Emmas Antwort, für Gesprächsgedächtnis
CREATE INDEX IF NOT EXISTS interaction_memory_user_idx ON interaction_memory (user_id, created_at);

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

-- ---------------------------------------------------------------- Emmas inneres Leben
-- Langzeitgedächtnis (wird nach jedem Denkzyklus als EMMA_memory.json nach Google Drive exportiert).
CREATE TABLE IF NOT EXISTS emma_memory (
  id          bigserial PRIMARY KEY,
  category    text NOT NULL,          -- goals | decisions | strategies | market_intel | learnings | people | preferences
  content     text NOT NULL,
  importance  int NOT NULL DEFAULT 3, -- 1 (Detail) … 5 (zentral)
  source      text,                   -- CHAT | SELF | JARVIS
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS emma_memory_rank_idx ON emma_memory (importance DESC, created_at DESC);

-- Themen, die Emma mit Irina besprechen möchte.
CREATE TABLE IF NOT EXISTS emma_agenda (
  id          bigserial PRIMARY KEY,
  topic       text NOT NULL,
  reason      text,
  status      text NOT NULL DEFAULT 'open',   -- open | done
  created_at  timestamptz NOT NULL DEFAULT now(),
  done_at     timestamptz
);

-- Jeder Denkzyklus von EMMA_COGNITIVE_LOOP.
CREATE TABLE IF NOT EXISTS emma_cycles (
  id            bigserial PRIMARY KEY,
  mode          text,                 -- MORNING | EVENING | WAKE | MANUAL
  wake_events   jsonb,
  thoughts      text,
  actions       jsonb,
  next_wake_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Gespräche zwischen EMMA, JARVIS und IRINA.
CREATE TABLE IF NOT EXISTS agent_dialogue (
  id          bigserial PRIMARY KEY,
  from_agent  text NOT NULL,
  to_agent    text NOT NULL,
  message     text,
  meta        jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS agent_dialogue_created_idx ON agent_dialogue (created_at);

-- ---------------------------------------------------------------- Budget (Phase 1: 0 €, hartes Limit 5 €)
-- Jeder KI-Aufruf wird mit geschätzten Kosten protokolliert. Im Free Tier kostet es real 0 €;
-- die Schätzung schützt davor, dass bei aktivierter Abrechnung unbemerkt Kosten entstehen.
CREATE TABLE IF NOT EXISTS llm_usage (
  id             bigserial PRIMARY KEY,
  workflow       text,
  input_chars    int,
  output_chars   int,
  est_cost_eur   numeric(12, 6) NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS llm_usage_created_idx ON llm_usage (created_at);

-- Listenpreis Gemini 2.5 Flash bei Abrechnung, konservativ 1 $ = 1 €: 0,30 € je 1 Mio. Input-Token,
-- 2,50 € je 1 Mio. Output-Token, ~4 Zeichen je Token. Preise hier anpassen, falls Google sie ändert.
CREATE OR REPLACE FUNCTION emma_llm_cost(in_chars int, out_chars int) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT round((COALESCE(in_chars, 0) / 4.0 * 0.30 + COALESCE(out_chars, 0) / 4.0 * 2.50) / 1000000, 6)
$$;

-- Geschätzte Kosten im laufenden Monat. Alle Workflows prüfen vor jedem KI-Aufruf gegen das Limit (5 €).
CREATE OR REPLACE FUNCTION emma_budget_spent() RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(est_cost_eur), 0) FROM llm_usage WHERE created_at >= date_trunc('month', now())
$$;

-- ---------------------------------------------------------------- Sichtbare Arbeitsspuren
-- Alles, was Emma sichtbar hinterlässt: Briefings, Protokolle, Notizen, Entwürfe, Kalendereinträge.
CREATE TABLE IF NOT EXISTS emma_artifacts (
  id          bigserial PRIMARY KEY,
  kind        text NOT NULL,     -- briefing | protokoll | wissen | entwurf | kalender
  title       text,
  url         text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS emma_artifacts_created_idx ON emma_artifacts (created_at);
