# EMMA n8n Workflow Audit

## Designentscheidung nach Review

Der vorherige Stand war als JSON-Bundle syntaktisch sauber, aber für echte n8n-Ausführung gab es vier Laufzeit-Risiken:

1. **Sub-Workflow-Aufrufe brauchen stabile Workflow-IDs.** Der Master-Orchestrator darf nicht nur auf sichtbare Canvas-Namen hoffen. Deshalb besitzt jetzt jeder Export eine stabile `id`, die identisch zum Workflow-Namen ist.
2. **LLM-Ausgaben sind nicht automatisch JSON-Felder.** Basic LLM Chain Nodes liefern typischerweise Text. Deshalb folgt auf jede LLM Chain ein Parser-Node, der Markdown-Fences entfernt, JSON extrahiert und Felder wie `business_model`, `legal_status` oder `strategic_breakthrough` wieder als `$json` verfügbar macht.
3. **Datenbank-Nodes dürfen den Gesamtfluss nicht hart stoppen.** SQLite/Postgres benötigen externe Credentials und Tabellen. Deshalb laufen DB-Nodes mit Retry und `continueOnFail`; lokale SQLite-Workflows legen Kern-Tabellen per `CREATE TABLE IF NOT EXISTS` an.
4. **Placeholder-Skills dürfen nicht nur NoOp sein.** Bitwarden und Drive geben jetzt strukturierte, sichere Aktionspläne zurück, auch wenn noch keine externen Schreib-Credentials verbunden sind.

## Was weiterhin extern konfiguriert sein muss

Diese Punkte können nicht allein durch den JSON-Export garantiert werden und müssen in der n8n-Instanz gesetzt werden:

- Google Gemini credential: `Google Gemini API`
- Telegram credential: `Telegram Metropolis`
- SQLite credential: `Metropolis SQLite`
- Postgres credential for Postgres-backed workflows
- Bei n8n Cloud: importierte Sub-Workflows müssen ihre stabile ID behalten oder der Master-Mapper muss auf die von n8n vergebenen IDs angepasst werden.
- Workflow Settings: Sub-Workflows müssen von anderen Workflows aufrufbar sein.

## Bundle-weite technische Checks

Das Tool `tools/validate_n8n_workflows.py` prüft:

- alle JSON-Dateien sind parsebar
- jeder Workflow hat eine stabile Top-Level-`id`
- jede Connection referenziert existierende Node-Namen
- Switch-Regeln und Switch-Ausgänge passen zusammen
- jede Basic LLM Chain hat Prompt, Modell-Verbindung und nachgelagerten JSON-Parser
- Gemini-Modelle sind auf `models/gemini-2.5-flash` standardisiert
- Webhooks sind `POST`
- Datenbank-Nodes haben `continueOnFail`
- `Execute Workflow`-Mappings verweisen auf Workflows, die im Bundle existieren

## Workflow-Abdeckung

| Workflow | Primärer Zweck | Laufzeit-Härtung |
| --- | --- | --- |
| `EMMA_MASTER_ORCHESTRATOR` | Omnichannel Intake, Routing, Sub-Workflow-Ausführung | Skill-Router, stabile Workflow-ID-Map, Originalinput-Weitergabe |
| `METROPOLIS_MULTI_AGENT_CORE` | Strategie/Risiko/Chance | Execute Trigger, Gemini 2.5, JSON-Parser je Agent |
| `EMMA_SELF_BUILDER` | Workflow-Generierung | Analyse-/Generate-Parser, DB/API-Nodes tolerant gegen externe Fehler |
| `GITHUB_ENGINE_V700` | GitHub-Issues/Reviews/Repo-Audit planen | JSON-Vertrag, Modellverkabelung, Parser |
| `ASANA_ENGINE_V700` | Aufgaben/Projektsteuerung | Execute Trigger, Modellverkabelung, Parser |
| `BITWARDEN_ENGINE_V700` | Vault-/Secret-Governance | Safe Function-Plan ohne Secret-Ausgabe |
| `DRIVE_ENGINE_V700` | Drive-/Datei-Aktionsplan | Safe Function-Plan ohne Schreib-Credentials |
| `CONTENT_ENGINE_V700` | Content-Erstellung | JSON-Vertrag, Parser |
| `SALES_ENGINE_V700` | Sales-Angebote | JSON-Vertrag, Parser |
| `LEAD_ENGINE_V700` | Lead-Analyse/CRM | JSON-Vertrag, Parser, Postgres tolerant |
| `LEGAL_ENGINE_V14` | Rechtliche Orientierung | JSON-Vertrag, Parser, SQLite tolerant |
| `FINANCE_ENGINE_V14` | CFO/Finanzanalyse | JSON-Vertrag, Parser, SQLite Table Bootstrap |
| `VENTURE_ENGINE_V14` | Geschäftsmodell/Scale-Plan | JSON-Vertrag, Parser, SQLite Table Bootstrap |
| `INTEL_ENGINE_V14` | OSINT/Analyse | JSON-Vertrag, Parser, SQLite Table Bootstrap |
| `SUPERNOVA_ENGINE_V_INFINITY` | High-Level Strategie | JSON-Vertrag, Parser, SQLite Table Bootstrap |
| `CRM_ENGINE_V700` | CRM Intake | Execute Trigger + Webhook, SQLite tolerant |
| `LOGGING_ENGINE_V700` | Registry Logging | Execute Trigger + Webhook, SQLite Table Bootstrap |
| `METROPOLIS_KPI_REGISTRY` | KPI Updates | Execute Trigger + Webhook, SQLite Table Bootstrap |
| `METROPOLIS_SYNC_BRIDGE` | Status Sync | Execute Trigger + Webhook, SQLite Table Bootstrap |
| `VECTOR_MEMORY_ENGINE_V700` | Postgres Memory Read | Execute Trigger, Postgres tolerant |
| `GOOGLE_SUITE_ENGINE_V700` | Google Workspace Planung | JSON-Vertrag, Parser |
| `SHOPIFY_ENGINE_V700` | Commerce-Aktionen planen | JSON-Vertrag, Parser |
| `WORDPRESS_ENGINE_V700` | WordPress Content | JSON-Vertrag, Parser |
| `DISCORD_ENGINE_V700` | Community/Social | JSON-Vertrag, Parser |
| `EMAIL_VALIDATION_ENGINE_V700` | E-Mail-Prüfung | JSON-Vertrag, Parser |
| `GUARDIAN_ENGINE_V700` | Risiko/Compliance | JSON-Vertrag, Parser |
| `KI_AGENT_ENGINE_V700` | KI-Agentensteuerung | JSON-Vertrag, Parser |
| `PRICING_ENGINE_V700` | Preisstrategie | JSON-Vertrag, Parser |
| `QUICKCHART_ENGINE_V700` | Chart JSON | JSON-Vertrag, Parser |
| `REACTIVATION_ENGINE_V700` | Winback | JSON-Vertrag, Parser |
| `SPOTIFY_ENGINE_V700` | Musik/Playlist-Analyse | JSON-Vertrag, Parser |
| `STREAMS_ENGINE_V700` | Live-Stream Planung | JSON-Vertrag, Parser |
| `EVOLUTION_ENGINE_V700` | Selbstoptimierung | JSON-Vertrag, Parser |
| `INTELLIGENCE_ENGINE_V700` | Strategische Analyse | JSON-Vertrag, Parser |

## Betriebs-Checkliste nach Import

1. Alle Credentials in n8n öffnen und testen.
2. Alle Sub-Workflows speichern, damit n8n interne IDs/Versionen aktualisiert.
3. Im Master-Orchestrator `EXECUTE_ENGINE` prüfen: Wenn n8n beim Import neue IDs vergibt, die Mapping-Werte auf diese IDs ändern.
4. Jeden Sub-Workflow einmal direkt mit `{ "text": "health check", "engine": "...", "source": "manual" }` ausführen.
5. Danach den Master-Orchestrator mit je einem Keyword pro Engine testen.
