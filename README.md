# EMMA / Metropolis – n8n Workflows

Früher waren es 34 Workflows, jetzt sind es **6**. Die rund 30 `*_ENGINE`-Workflows waren fast identisch
(Trigger → Gemini → evtl. speichern) und liefen nicht: Ihre Verbindungen zeigten auf Node-IDs statt auf
Node-Namen, und alle nutzten das abgeschaltete `gemini-1.5-pro`. Deshalb stand im Daily Report überall **0**.

| Workflow | Zweck | Trigger |
|---|---|---|
| `EMMA_MASTER_ORCHESTRATOR` | Telegram/WhatsApp/Social rein → Mayor entscheidet → Engine → Antwort | Telegram, Webhooks `metropolis-core`, `metropolis-whatsapp`, `metropolis-social` |
| `EMMA_ENGINE_HUB` | **Eine** Engine mit Rollen-Registry (FINANCE, LEGAL, INTEL, VENTURE, SUPERNOVA, LEAD, SALES, CONTENT, SOCIAL, WORDPRESS, SHOPIFY, GITHUB, TASKS, GUARDIAN, …) | Aufruf durch Orchestrator, Webhook `emma-engine`, alte Pfade `finance-engine`, `legal-engine`, `intel-engine`, `venture-engine`, `supernova` |
| `METROPOLIS_DATA_GATEWAY` | Logs, Sync, KPIs, CRM-Leads in die DB | alte Pfade `logging-engine`, `metropolis-sync`, `metropolis-kpi`, `crm-engine` |
| `METROPOLIS_MULTI_AGENT_CORE` | Strategie-, Risiko- und Opportunity-Agent parallel, gemeinsame Antwort | Webhook `multi-agent-core` |
| `EMMA_SELF_BUILDER` | Baut neue Workflows – **mit Duplikat-Schutz**, legt sie inaktiv an | Webhook `emma-self-builder` |
| `EMMA_DAILY_REPORT` | Tagesbericht an Telegram um 08:00 | Zeitplan |

Neue Engine = ein neuer Eintrag in `ENGINES` im Node **Build Prompt** des `EMMA_ENGINE_HUB`, **kein neuer Workflow**.

## Was die Engines schreiben (Grundlage für den Daily Report)

- jeder Engine-Lauf → `engine_runs` (inkl. `risk_level`)
- Aufgaben aus der Antwort → `emma_tasks`
- `risk_level = HIGH` → `emma_approvals` (pending)
- LEAD-Kontakte → `crm_leads`

## Einrichten / Migration

1. `schema.sql` einmal gegen die Postgres-DB ausführen. Das Script ist idempotent, bestehende Tabellen bleiben erhalten.
   Alle Workflows nutzen jetzt **nur noch Postgres**. Vorher schrieb der Orchestrator nach SQLite, gelesen wurde aber aus Postgres.
2. In n8n **alle alten** Workflows deaktivieren und löschen: alle `*_ENGINE_V700`, `*_ENGINE_V14`,
   `SUPERNOVA_ENGINE_V_INFINITY`, `METROPOLIS_KPI_REGISTRY`, `METROPOLIS_V14_SYNC_BRIDGE`, den alten Daily-Report-Workflow
   und alle vom Self-Builder erzeugten `EMMA_COGNITIVE_*`. Sonst kollidieren die Webhook-Pfade.
3. Die 6 JSON-Dateien importieren.
4. Im `EMMA_MASTER_ORCHESTRATOR` im Node **EXECUTE_ENGINE** den Workflow `EMMA_ENGINE_HUB` auswählen.
5. Credentials prüfen (Gemini, Postgres, Telegram, Header Auth mit `X-N8N-API-KEY` für die n8n-API).
6. Aktivieren. Pro Telegram-Bot darf nur **ein** aktiver Workflow einen Telegram-Trigger haben.

## Prüfen

```bash
python3 tools/validate_workflows.py
```

Das Script prüft kaputte Verbindungen, doppelte Workflow-Namen und Webhook-Pfade, abgeschaltete Gemini-Modelle und
SQL mit direkt eingesetzten Werten. Es läuft auch automatisch als GitHub Action.
