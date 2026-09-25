-- EMMA / Metropolis – Postgres-Schema der n8n-Seite.
-- Idempotent: kann beliebig oft ausgeführt werden, bestehende Daten bleiben erhalten.
--
-- WICHTIG: Gedächtnis, Aufgaben, Freigaben, Agenda und Chatverlauf gehören core-os.
-- Dafür gibt es hier bewusst KEINE Tabellen (kein zweites Gedächtnis). n8n spricht dafür die core-os-API an.
-- Wer frühere Versionen dieses Schemas ausgeführt hat, hat evtl. noch emma_memory, emma_tasks, emma_approvals,
-- emma_agenda, interaction_memory. Sie werden nicht mehr benutzt und hier absichtlich NICHT gelöscht.
-- Übernahme nach core-os und Löschen entscheidet der Nutzer.

-- ---------------------------------------------------------------- Betriebsprotokolle der n8n-Seite
-- Jeder Lauf des EMMA_ENGINE_HUB.
CREATE TABLE IF NOT EXISTS engine_runs (
  id          bigserial PRIMARY KEY,
  engine      text NOT NULL,
  session_id  text,
  input       text,
  output      jsonb,
  risk_level  text NOT NULL DEFAULT 'LOW',   -- LOW | MEDIUM | HIGH
  status      text NOT NULL DEFAULT 'ok',    -- ok | no_json | parse_error
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE engine_runs ADD COLUMN IF NOT EXISTS session_id text;
CREATE INDEX IF NOT EXISTS engine_runs_created_at_idx ON engine_runs (created_at);

-- Denkzyklen von EMMA_COGNITIVE_LOOP (was gedacht und geplant wurde).
CREATE TABLE IF NOT EXISTS emma_cycles (
  id            bigserial PRIMARY KEY,
  mode          text,                 -- MORNING | EVENING | WAKE
  wake_events   jsonb,
  thoughts      text,
  actions       jsonb,
  next_wake_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Ergebnis jeder einzelnen Aktion – Fehler werden als Fehler geloggt, nicht als erledigt.
CREATE TABLE IF NOT EXISTS emma_action_log (
  id           bigserial PRIMARY KEY,
  cycle_id     bigint,
  action_type  text NOT NULL,
  ok           boolean NOT NULL,
  detail       text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS emma_action_log_created_idx ON emma_action_log (created_at);

-- Ausführungswarteschlange für Vorschläge. Die ENTSCHEIDUNG liegt in core-os (core_os_approval_id);
-- hier liegt nur, WAS nach der Freigabe ausgeführt werden soll, und das Ergebnis.
CREATE TABLE IF NOT EXISTS n8n_action_queue (
  id                   bigserial PRIMARY KEY,
  kind                 text NOT NULL,   -- run_engine | write_note | write_draft | calendar_event | create_workflow
  summary              text NOT NULL,
  payload              jsonb NOT NULL DEFAULT '{}'::jsonb,
  source               text,
  core_os_approval_id  text,
  status               text NOT NULL DEFAULT 'proposed',   -- proposed | running | done | failed
  result               text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  started_at           timestamptz,
  finished_at          timestamptz
);
CREATE INDEX IF NOT EXISTS n8n_action_queue_status_idx ON n8n_action_queue (status, core_os_approval_id);

-- Sichtbare Arbeitsspuren (Briefings, Protokolle, Notizen, Entwürfe, Kalendereinträge) mit Link.
CREATE TABLE IF NOT EXISTS emma_artifacts (
  id          bigserial PRIMARY KEY,
  kind        text NOT NULL,     -- briefing | protokoll | wissen | entwurf | kalender
  title       text,
  url         text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS emma_artifacts_created_idx ON emma_artifacts (created_at);

-- Log- und Sync-Events aus METROPOLIS_DATA_GATEWAY.
CREATE TABLE IF NOT EXISTS emma_events (
  id          bigserial PRIMARY KEY,
  source      text,
  level       text NOT NULL DEFAULT 'INFO',
  message     text,
  payload     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- Geschäftsdaten
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

-- Vom Self-Builder entworfene Workflows. Angelegt (inaktiv) werden sie erst nach Freigabe in core-os.
CREATE TABLE IF NOT EXISTS workflow_registry (
  id             bigserial PRIMARY KEY,
  workflow_id    text,
  workflow_name  text,
  workflow_json  jsonb,
  purpose        text,
  created_by     text,
  status         text NOT NULL DEFAULT 'pending_approval',   -- pending_approval | created_inactive | failed
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE workflow_registry ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE workflow_registry ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending_approval';

-- ---------------------------------------------------------------- KI-Budget (geschätzt!)
-- Jeder KI-Aufruf wird mit GESCHÄTZTEN Kosten protokolliert. Das Limit (Standard 5 €, EMMA_BUDGET_EUR) ist nur so
-- genau wie diese Schätzung: Zeichenzahl / 4 ≈ Token, Listenpreis Gemini 2.5 Flash. Im Free Tier sind die echten
-- Kosten 0 €. Die tatsächliche Abrechnung steht nur in der Google-Cloud-Konsole. Dort zusätzlich ein Budget-Alarm setzen.
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

-- Geschätzte Kosten im laufenden Monat. Jeder Workflow prüft das VOR jedem KI-Aufruf (fail-closed).
CREATE OR REPLACE FUNCTION emma_budget_spent() RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(est_cost_eur), 0) FROM llm_usage WHERE created_at >= date_trunc('month', now())
$$;
