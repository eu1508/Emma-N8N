# EMMA / Metropolis – n8n Workflows

> **Status: GEBAUT, nicht LIVE.** Geprüft mit Validator, Syntax-Check und Logik-Tests auf Testdaten. In der produktiven
> n8n-Instanz ist noch nichts ausgeführt worden. Die core-os-API-Endpunkte unten sind **unbestätigt**, sie müssen gegen
> core-os abgeglichen werden, bevor irgendetwas aktiviert wird.

## Grundregeln (feste Entscheidungen des Nutzers)

- **core-os ist die einzige Wahrheit** für Gedächtnis, Aufgaben, Freigaben und die Telegram-Brücke. n8n hat **kein**
  eigenes Gedächtnis und keine eigenen Aufgaben- oder Freigabetabellen.
- **Genau ein Telegram-Empfänger:** `emma-telegram-worker` (core-os). n8n empfängt kein Telegram.
- **Keine proaktiven Telegram-Nachrichten** aus n8n. Der Tagesreport kommt von core-os (20:00).
- **JARVIS bleibt in Quarantäne.** In n8n gibt es keinen Jarvis-Workflow.
- **Nichts mit Wirkung ohne Freigabe:** Engines, Dokumente, Kalendereinträge und neue Workflows werden nur
  **vorgeschlagen** und erst nach einer in core-os bestätigten Freigabe ausgeführt.

## Workflows (9)

| Workflow | Zweck | Auslöser |
|---|---|---|
| `EMMA_MASTER_ORCHESTRATOR` | Beantwortet Anfragen, die core-os weiterreicht. Mit `user_verified: true` darf er sich Dinge merken (über core-os) und Engine- oder Termin-**Vorschläge** machen. Ohne ist er nur lesend. | Webhook `metropolis-core` (Auth) |
| `EMMA_COGNITIVE_LOOP` | Denkschleife: 07:00 Morgen-Routine, 21:30 Abend-Reflexion und selbst geplante Weckzeiten. Legt Aufgaben und Erinnerungen in core-os an und erstellt Vorschläge. Schreibt ein Briefing bzw. Arbeitsprotokoll nach Drive. | Cron 07:00, 21:30 · Timer · Test-Knopf |
| `EMMA_WAKE_TIMER` | Wartet per Wait-Node bis zur geplanten Weckzeit (10 min bis 7 Tage) und startet dann den Loop. Ersetzt den alten 15-Minuten-Herzschlag. | Sub-Workflow |
| `EMMA_PROPOSE` | Legt Vorschläge in der Warteschlange ab und fragt die Freigabe bei core-os an | Sub-Workflow |
| `EMMA_APPROVED_EXECUTOR` | Führt **nur** aus, was core-os freigegeben hat, loggt Erfolg oder Fehler und meldet das Ergebnis an core-os zurück | Webhook `emma-approved` (Auth) · nach jedem Loop · manuell |
| `EMMA_ENGINE_HUB` | Eine Engine mit allen Fach-Rollen (FINANCE, LEGAL, SALES, CONTENT, LEAD, …) statt 30 Kopien | Sub-Workflow · Webhook `emma-engine` (Auth) |
| `EMMA_SELF_BUILDER` | Entwirft einen Workflow nur aus erlaubten Node-Typen. Angelegt wird er erst nach Freigabe und dann **inaktiv**. | Webhook `emma-self-builder` (Auth) |
| `METROPOLIS_MULTI_AGENT_CORE` | Strategie-, Risiko- und Opportunity-Agent parallel | Webhook `multi-agent-core` (Auth) |
| `METROPOLIS_DATA_GATEWAY` | Logs, Sync, KPIs, CRM-Leads | Webhooks `logging-engine`, `metropolis-sync`, `metropolis-kpi`, `crm-engine` (Auth) |

Entfernt wurden: `EMMA_JARVIS` (Quarantäne), `EMMA_DAILY_REPORT` (core-os schickt den Tagesreport), alle Telegram-Trigger,
die ungenutzten Pfade `metropolis-whatsapp`, `metropolis-social`, `finance-engine`, `legal-engine`, `intel-engine`,
`venture-engine` und `supernova` sowie der Gedächtnis-Export `EMMA_memory.json`.

## Freigabe-Ablauf

```
Loop / Orchestrator / Self-Builder
   └─ EMMA_PROPOSE ── n8n_action_queue (status=proposed) ── POST core-os /api/v1/approvals
                                                                   │  Irina gibt in core-os frei
core-os ── POST n8n /webhook/emma-approved ─┐                     │
Loop (07:00/21:30) ─────────────────────────┴─ EMMA_APPROVED_EXECUTOR
      GET core-os /api/v1/approvals?source=n8n&status=approved
      → nur passende Einträge der Warteschlange (proposed → running)
      → ausführen → Ergebnis loggen (done/failed) → POST core-os /api/v1/approvals/{id}/result
```

Der Executor fragt den Freigabestatus immer selbst bei core-os ab. Der Aufruf von `emma-approved` ist nur ein Anstoß,
keine Freigabe. Jeder Eintrag der Warteschlange wird höchstens einmal ausgeführt (`proposed → running`).

## core-os-API: was n8n braucht (UNBESTÄTIGT)

Die Endpunkte sind aus den Anforderungen abgeleitet, nicht aus dem core-os-Code. Der liegt noch nicht auf GitHub.
Sie müssen mit core-os abgeglichen werden. Was fehlt, wird in core-os ergänzt oder hier angepasst, **nicht** durch
eigene Tabellen ersetzt.

| Methode & Pfad | Wofür | Erwartete Antwort | Status |
|---|---|---|---|
| `GET /api/v1/context?for=n8n` | Gedächtnis, letzter Chat, offene Aufgaben, Themen | `{ memory: [], recent_chat: [], tasks: [], agenda: [] }` | offen |
| `POST /api/v1/memory` | Erinnerung speichern | `{ id }` | offen |
| `POST /api/v1/tasks` | Aufgabe anlegen | `{ id }` | offen |
| `POST /api/v1/tasks/{id}/complete` | Aufgabe erledigen | `{ ok }` | offen |
| `POST /api/v1/approvals` | Freigabe anfragen (`source`, `reference`, `kind`, `summary`) | `{ id }` | offen |
| `GET /api/v1/approvals?source=n8n&status=approved` | freigegebene Vorschläge | `[ { id } ]` oder `{ items: [...] }` | offen |
| `POST /api/v1/approvals/{id}/result` | Ergebnis melden (`ok`, `detail`, `url`) | `{ ok }` | offen |
| core-os → `POST {n8n}/webhook/emma-approved` | Anstoß nach Freigabe (Header-Auth) | – | offen |
| core-os → `POST {n8n}/webhook/metropolis-core` | Nachricht weiterreichen (`text`, `user_verified`) | `{ reply, proposals }` | offen |

Solange diese Punkte offen sind, bricht jeder Workflow, der core-os braucht, sauber ab (fail-closed). Er arbeitet
dann nicht mit einem Ersatzspeicher weiter.

## Sicherheit

- **Webhooks:** Alle verlangen Header-Auth über das Credential **„EMMA Webhook Auth“** (eigener, zufälliger Schlüssel).
  Den n8n-API-Key dafür nicht wiederverwenden. Der Validator bricht bei Webhooks ohne Auth ab.
- **Rechte im Code:** Der Orchestrator lässt Erinnerungen, Termine und Engines nur mit `user_verified: true` zu, und das
  auch dann nur als Vorschlag. Kontext wird über eine feste core-os-Abfrage geholt, nie über einen Absender aus dem Body.
- **Prompt-Injection:** Kalender-, Gedächtnis- und Chat-Inhalte stehen im Prompt als `<daten>`. Wacht der Loop über eine
  selbst geplante Weckzeit auf, ist der Anlass ungeprüft, und `remember` ist gesperrt. Termine übernehmen nur Titel und
  Zeit, nie Text von Aufrufern in die Beschreibung.
- **Self-Builder:** Nur erlaubte Node-Typen: kein Code, kein Execute Command, kein beliebiger HTTP-Request, keine Webhooks.
  Angelegt wird erst nach Freigabe und immer inaktiv.
- **Öffentliches Repo:** keine Secrets, Chat-IDs oder internen Adressen. Konfiguration über Umgebungsvariablen (s. u.).
  Der Validator prüft auf private IPs und fest eingetragene Chat-IDs. Die GitHub Action läuft mit `contents: read`.

## KI-Budget (Schätzung!)

- Alle KI-Nodes nutzen **Gemini 2.5 Flash** (Free Tier).
- Vor **jedem** KI-Aufruf (Orchestrator, Loop, Engine Hub, Self-Builder mit 2 Aufrufen, Multi-Agent) steht derselbe
  Budget-Check. Er ist fail-closed: Ist die Datenbank nicht erreichbar, gibt es keinen KI-Aufruf.
- Jeder Aufruf wird in `llm_usage` mit **geschätzten** Kosten geloggt (Zeichen / 4 ≈ Token, Listenpreis).
- Das Limit (Standard 5 €, `EMMA_BUDGET_EUR`) ist **nur so genau wie diese Schätzung**. Die echte Abrechnung zeigt nur die
  Google-Cloud-Konsole. Dort zusätzlich einen Budget-Alarm setzen.

## Arbeitsspuren (Google Drive → Emma → EMMA_ARBEITSSPUREN)

| Ordner | Inhalt | Wann |
|---|---|---|
| `01_Briefings` | „Briefing JJJJ-MM-TT“: Gedanken, Termine, Plan, offene Vorschläge und Aufgaben | 07:00 (abschaltbar: `EMMA_DAILY_DOCS=off`) |
| `02_Wissen` | „Wissen – …“ | nach Freigabe eines `write_note`-Vorschlags |
| `03_Entwuerfe` | „Entwurf – …“, wird nie verschickt | nach Freigabe eines `write_draft`-Vorschlags |
| `04_Arbeitsprotokoll` | „Arbeitsprotokoll JJJJ-MM-TT“: Zyklen, Ergebnisse (✅/❌), Vorschläge, Spuren | 21:30 (abschaltbar wie oben) |

Briefing und Protokoll werden ohne Freigabe geschrieben. Sie landen nur in diesem eigenen Ordner und sind die vom
Nutzer gewünschte sichtbare Spur. Soll auch das erst nach Freigabe passieren, `EMMA_DAILY_DOCS=off` setzen.

## Einrichten

1. **Umgebungsvariablen** im n8n-Container setzen (nicht ins Repo):
   - `EMMA_CORE_OS_URL`: Basis-URL von core-os
   - optional `EMMA_BUDGET_EUR` (Standard 5) und `EMMA_DAILY_DOCS` (`on`/`off`)
   - Nötig ist außerdem, dass Code-Nodes auf Umgebungsvariablen zugreifen dürfen (`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`).
     Ohne diese Freigabe bricht jeder Lauf mit „EMMA_CORE_OS_URL ist nicht gesetzt“ ab. Die Alternative: den Wert im
     Node „Konfiguration“ direkt in n8n eintragen, aber nie zurück ins Repo.
2. **Datenbank:** `schema.sql` ausführen (idempotent).
3. **Credentials** in n8n anlegen und zuordnen: Gemini, Postgres, Google Calendar, Google Drive, **EMMA Webhook Auth**
   (Header Auth für eingehende Webhooks), **core-os API** (Header Auth für Aufrufe an core-os), Header Auth mit n8n-API-Key
   (nur Executor, zum Anlegen freigegebener Workflows).
4. **Sub-Workflows verknüpfen** in allen `Execute Workflow`-Nodes: `EMMA_ENGINE_HUB`, `EMMA_PROPOSE`,
   `EMMA_APPROVED_EXECUTOR`, `EMMA_WAKE_TIMER`, `EMMA_COGNITIVE_LOOP`.
5. **Erst wenn die core-os-Endpunkte bestätigt sind:** im Loop „Jetzt testen (Briefing)“ ausführen, danach aktivieren.

## Offene Punkte

- core-os-Endpunkte oben abgleichen oder in core-os ergänzen.
- core-os muss nach einer Freigabe `emma-approved` aufrufen (oder der Executor läuft nur um 07:00 und 21:30).
- Alte Tabellen `emma_memory`, `emma_tasks`, `emma_approvals`, `emma_agenda`, `interaction_memory` aus früheren
  Schema-Versionen: nach core-os übernehmen oder löschen. Das entscheidet der Nutzer, das Schema löscht nichts.
- Tagesreport von core-os (20:00) könnte `emma_artifacts` und `llm_usage` mit anzeigen. Dafür bräuchte core-os Lesezugriff.

## Alte Workflows: was wo weiterlebt

Das stammt aus `ALL_WORKFLOWS_BACKUP.json` (Stand Mai, 75 Workflows). Live laufen laut `N8N_WORKFLOW_KARTE.md` (14.09.)
237 Workflows. **Nichts löschen, was nicht in dieser Liste steht, und vorher in n8n exportieren.**

| Alt | Lebt weiter in |
|---|---|
| alle `*_ENGINE_V700`, `*_ENGINE_V14`, `EMMA_C500_*_ENGINE_*`, `SUPERNOVA_ENGINE_*`, `EMMA_SUPERNOVA_V∞`, `METROPOLIS_DYNAMIC_ENGINE`, `INTELLIGENCE_SECURITY_V1000` | `EMMA_ENGINE_HUB` |
| `METROPOLIS_MASTER_ORCHESTRATOR_*`, `EMMA_MASTER_ORCHESTRATOR_V2_ULTIMATE`, `EMMA_CLOUD_OS_V1/V2`, `EMMA_WORLDMASTER_SCO`, `EMMA_SUPERNOVA_MASTER_BRAIN` | `EMMA_MASTER_ORCHESTRATOR` (als Anhängsel von core-os) |
| `EMMA_CALENDAR_SIMPLE`, `EMMA_CALENDAR_MANAGER_FIXED` | Termin-Vorschläge über Orchestrator und Executor |
| `EMMA_DAILY_EVOLUTION` | Abend-Reflexion im `EMMA_COGNITIVE_LOOP` |
| `EMMA_MEMORY_ENGINE`, `EMMA_MEMORY_SYNC`, `EMMA_CONTEXT_ENGINE`, `VECTOR_MEMORY_ENGINE` | core-os (Gedächtnis) |
| `EMMA_COUNCIL_500_TEMPLATE` | Freigabe-Ablauf über core-os |
| `WF_02_Daily_Mayor_Briefing`, `WF_03_Hourly_Pulse_Check` | Tagesreport von core-os + Briefing-Dokument |
| `EMMA_AGENT_HUB` | `METROPOLIS_MULTI_AGENT_CORE` |
| `CRM_ENGINE_V700_CLOUD`, `LOGGING_ENGINE`, `METROPOLIS_KPI_REGISTRY`, `METROPOLIS_V14_SYNC_BRIDGE` | `METROPOLIS_DATA_GATEWAY` |
| `EMMA_SELF_BUILDER_*`, `EMMA_WORKFLOW_CREATOR`, alle `EMMA_COGNITIVE_*` | `EMMA_SELF_BUILDER` |
| leere Hüllen: `LOCAL_AGENT_V2`, `pc_action_node…`, `My_Sub_Workflow_3`, `FINANZMOTOR_V700`, `EMMA_SUPERVISOR_V1` | hatten keine Funktion |

**Behalten, weil sie eine eigene Aufgabe haben** (von Duplikaten nur eine Kopie): `SYNCHRONISIERE_SHOPIFY_MIT`,
`TÄGLICHER_SALES_REPORT`, `ERSTELLE_EMAIL-AUTOMATION` (mit dem Sales-Report vergleichen), `CONTENT_MEDIA_ENGINE`,
`CONTENT_MEDIA_ADS_ENGINE`, `WF_11_Product_Listing_Factory`, `WF_15_Revenue_Discovery_Cluster`,
`WF_16_Conversion_Offer_Engine`, `WF_21_Email_Funnel_Automator`, `WF_22_Partnership_Affiliate_Scout`,
`EMMA_AI_BUSINESS_MASTER`, `EMMA_STATUS_REPORT_IMMO`, `EMMA_CALENDAR_QUICK_FIX`, `CRM_ENGINE_V700` (Google-Sheets-CRM),
`EMMA_SKILLS_SH_DAILY_WATCHER`. Workflows mit eigenem Telegram-Trigger (z. B. `EMMA_C500_CORE_EMMA_SUPERNOVA_V_`)
dürfen nicht an @WorldMaster_Bot hängen, denn einziger Empfänger ist core-os.

**Google-Kalender:** Es gibt über 30 Kalender „EMMA | …“, einen pro altem Workflow. Genutzt wird nur noch „EMMA“.

## Prüfen

```bash
python3 tools/validate_workflows.py
```

Das Script prüft kaputte Verbindungen, doppelte Namen und Webhook-Pfade, Webhooks ohne Auth, Telegram-Trigger,
abgeschaltete Modelle, SQL-Injection-Muster, Zugriffe auf core-os-Tabellen, private IPs und Chat-IDs.
Es läuft auch automatisch als GitHub Action.
