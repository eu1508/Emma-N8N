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
| `EMMA_COGNITIVE_LOOP` | Denkschleife: 07:00 Morgen-Routine, 21:30 Abend-Reflexion und selbst geplante Weckzeiten (höchstens `EMMA_MAX_WAKES_PER_DAY` pro Tag; ein selbst geplantes Aufwachen darf nur noch EIN weiteres planen). Legt Aufgaben und Erinnerungen in core-os an und erstellt Vorschläge. Schreibt ein Briefing bzw. Arbeitsprotokoll nach Drive. | Cron 07:00, 21:30 · Timer · Test-Knopf |
| `EMMA_WAKE_TIMER` | Wartet per Wait-Node bis zur geplanten Weckzeit (10 min bis 7 Tage) und startet dann den Loop. Ersetzt den alten 15-Minuten-Herzschlag. | Sub-Workflow |
| `EMMA_PROPOSE` | Prüft Vorschläge (Art, Inhalt, Größe – Ungültiges bricht laut ab), legt sie in der Warteschlange ab und fragt die Freigabe bei core-os an: höchstens `EMMA_MAX_APPROVALS_PER_DAY` pro Tag und nicht in der Ruhezeit. Der Rest wartet und wird später nachgeholt. | Sub-Workflow |
| `EMMA_APPROVED_EXECUTOR` | Führt **nur** aus, was core-os ausdrücklich als freigegeben meldet (fail-closed), prüft neue Workflows **erneut** gegen die Allowlist, loggt Erfolg oder Fehler und meldet das Ergebnis an core-os zurück | Webhook `emma-approved` (Auth) · nach jedem Loop · manuell |
| `EMMA_ENGINE_HUB` | Eine Engine mit allen Fach-Rollen (FINANCE, LEGAL, SALES, CONTENT, LEAD, …) statt 30 Kopien | Sub-Workflow · Webhook `emma-engine` (Auth) |
| `EMMA_SELF_BUILDER` | Entwirft einen Workflow nur aus erlaubten Node-Typen (ohne Zugangsdaten und Umgebungszugriff, höchstens 25 Nodes). Angelegt wird er erst nach Freigabe und dann **inaktiv**. | Webhook `emma-self-builder` (Auth) |
| `METROPOLIS_MULTI_AGENT_CORE` | Strategie-, Risiko- und Opportunity-Agent parallel | Webhook `multi-agent-core` (Auth) |
| `METROPOLIS_DATA_GATEWAY` | Logs, Sync, KPIs, CRM-Leads | Webhooks `logging-engine`, `metropolis-sync`, `metropolis-kpi`, `crm-engine` (Auth) |

Entfernt wurden: `EMMA_JARVIS` (Quarantäne), `EMMA_DAILY_REPORT` (core-os schickt den Tagesreport), alle Telegram-Trigger,
die ungenutzten Pfade `metropolis-whatsapp`, `metropolis-social`, `finance-engine`, `legal-engine`, `intel-engine`,
`venture-engine` und `supernova` sowie der Gedächtnis-Export `EMMA_memory.json`.

## Freigabe-Ablauf

```
Loop / Orchestrator / Self-Builder
   └─ EMMA_PROPOSE ── prüfen ── n8n_action_queue (status=proposed)
        └─ Anfrage nur, wenn Tagesobergrenze und Ruhezeit sie erlauben ── POST core-os /api/v1/approvals
                                                                              │  Irina gibt in core-os frei
core-os ── POST n8n /webhook/emma-approved ─┐                                │
Loop (07:00 / 21:30 / Weckzeit) ────────────┴─ EMMA_APPROVED_EXECUTOR
      GET core-os /api/v1/approvals   → nur Einträge, die selbst den Status "approved" tragen, zählen
      → nur passende Einträge der Warteschlange (proposed → running)
      → Workflows: Allowlist erneut prüfen → ausführen
      → Ergebnis loggen (done/failed) → POST core-os /api/v1/approvals/{id}/result
```

Der Executor fragt den Freigabestatus immer selbst bei core-os ab. Der Aufruf von `emma-approved` ist nur ein Anstoß,
keine Freigabe. Ignoriert core-os die Filter der Abfrage oder liefert es etwas anderes als eine Liste, führt der Executor
nichts aus (fail-closed). Jeder Eintrag der Warteschlange wird höchstens einmal ausgeführt (`proposed → running`).
Was in der Warteschlange steht, wird vor dem Ausführen nicht blind vertraut: neue Workflows laufen noch einmal durch dieselbe
Allowlist wie im Self-Builder.

### Freigabe-Anfragen: Obergrenze und Ruhezeit

Jede Anfrage an core-os ist eine Nachricht an Irina und zählt deshalb wie ein Budget:

- höchstens `EMMA_MAX_APPROVALS_PER_DAY` Anfragen pro Kalendertag (Standard 5, `0` = gar keine),
- keine Anfragen in der Ruhezeit `EMMA_QUIET_HOURS` (Standard `22-7`, Europe/Berlin),
- was nicht gesendet werden darf, bleibt in der Warteschlange (`approval_requested_at` leer, im Loop-Prompt als
  „Anfrage steht noch aus“ sichtbar) und wird beim nächsten Lauf von `EMMA_PROPOSE` nachgeholt (der Loop stößt das nach jedem Zyklus an),
- schlägt die Anfrage fehl, wird sie zurückgesetzt und in `emma_events` als Fehler protokolliert.

n8n sendet selbst **keine** Telegram-Nachrichten. Ob und wie core-os eine Freigabe-Anfrage weitergibt, entscheidet core-os.

## core-os-API: was n8n braucht und was es in core-os schon gibt

Die Endpunkte sind aus den Anforderungen abgeleitet. Die Spalte „In core-os“ vergleicht sie mit dem core-os-Stand vom
25.09.2026 (core-os liegt nicht in diesem Repo). Was fehlt, wird in core-os ergänzt oder hier angepasst, **nicht** durch
eigene Tabellen ersetzt. Solange etwas offen ist, bricht der betroffene Workflow sauber ab (fail-closed).

| Was n8n aufruft | Wofür | Erwartete Antwort | In core-os | Folge / Anpassung |
|---|---|---|---|---|
| `GET /api/v1/context?for=n8n` | Gedächtnis, letzter Chat, offene Aufgaben, Themen | `{ memory: [], recent_chat: [], tasks: [], agenda: [] }` (alle vier Felder müssen Listen sein) | **offen** | Orchestrator und Loop brechen ohne gültigen Kontext ab, kein KI-Aufruf |
| `POST /api/v1/memory` | Erinnerung speichern | `{ id }` | **anders:** `POST /api/v1/memory/facts` (`topic`, `content`, `source_ref`, `confidence` als Query-Parameter), Suche `GET /api/v1/memory/search?q=` | Pfad und Format angleichen |
| `POST /api/v1/tasks` | Aufgabe anlegen | `{ id }` | vorhanden (`title`, `priority`, `owner_bot`, `due_at`) | Antwortformat prüfen |
| `POST /api/v1/tasks/{id}/complete` | Aufgabe erledigen | `{ ok }` | **anders:** `PATCH /api/v1/tasks/{id}` | anpassen |
| `POST /api/v1/approvals` | Freigabe anfragen (`source`, `reference`, `kind`, `summary`) | `{ id }` | **offen** (Freigaben entstehen dort aus Ereignissen über `POST /api/v1/events`) | ohne diesen Endpunkt kann n8n nichts vorschlagen |
| `GET /api/v1/approvals?source=n8n&status=approved` | freigegebene Vorschläge | Liste oder `{ approvals \| items \| data: [...] }` | **teilweise:** `GET /api/v1/approvals` liefert `{ approvals: [ { id, decision_status, … } ] }` ohne Filter | der Executor filtert selbst nach dem Status und lässt alles ohne Status „approved“ liegen |
| `POST /api/v1/approvals/{id}/result` | Ergebnis melden (`ok`, `detail`, `url`) | `{ ok }` | **offen** | Ergebnis bleibt nur in n8n (`n8n_action_queue`) |
| core-os → `POST {n8n}/webhook/emma-approved` | Anstoß nach Freigabe (Header-Auth) | – | **offen** | sonst läuft der Executor nur nach dem Loop |
| core-os → `POST {n8n}/webhook/metropolis-core` | Nachricht weiterreichen (`text`, `user_verified`) | `{ reply, proposals }` | **offen** | ohne Aufruf nutzt core-os den Orchestrator nicht |

Schreibzugriffe auf core-os können ein Token verlangen (Header-Auth). Es gehört ins n8n-Credential **„core-os API“**, nie in einen Workflow.

## Sicherheit

- **Webhooks:** Alle verlangen Header-Auth über das Credential **„EMMA Webhook Auth“** (eigener, zufälliger Schlüssel).
  Den n8n-API-Key dafür nicht wiederverwenden. Der Validator bricht bei Webhooks ohne Auth, mit `authentication=none` oder
  ohne zugeordnetes Credential ab (`tools/test_validator.py` beweist das).
- **Rechte im Code:** Der Orchestrator lässt Erinnerungen, Termine und Engines nur mit `user_verified: true` zu, und das
  auch dann nur als Vorschlag. Kontext wird über eine feste core-os-Abfrage geholt, nie über einen Absender aus dem Body.
- **Freigaben:** Ausgeführt wird nur, was core-os selbst als „approved“ meldet. Alles andere, auch eine unerwartete Antwort,
  führt zu nichts (fail-closed).
- **Prompt-Injection:** Kalender-, Gedächtnis-, Chat-, Aufgaben- und Themeninhalte sowie frühere Gedanken und Vorschläge
  stehen im Prompt als `<daten>`. Ein `</daten>` im Fremdtext wird entschärft und kann den Block nicht schließen. Fehlt der
  Kontext von core-os oder ist er unvollständig, gibt es keinen KI-Aufruf. Wacht der Loop über eine selbst geplante Weckzeit auf,
  ist der Anlass ungeprüft: `remember` ist gesperrt, es darf nur noch ein weiteres Aufwachen geplant werden, und pro Tag gibt
  es höchstens `EMMA_MAX_WAKES_PER_DAY` solche Zyklen. Termine übernehmen nur Titel und Zeit, nie Text von Aufrufern.
- **Self-Builder:** Nur erlaubte Node-Typen: kein Code, kein Execute Command, kein beliebiger HTTP-Request, keine Webhooks,
  keine Zugangsdaten und kein Zugriff auf Umgebungsvariablen in den Parametern, höchstens 25 Nodes. Dieselbe Prüfung läuft
  beim Entwurf UND noch einmal vor dem Anlegen. Angelegt wird erst nach Freigabe, immer inaktiv und ohne Credentials, die
  der Nutzer vor dem Aktivieren selbst zuordnet. Der Validator prüft, dass beide Stellen dieselbe Allowlist haben.
- **Kein Telegram, kein JARVIS in n8n:** Der Validator lehnt jeden Telegram-Node und jeden Aufruf von `api.telegram.org`
  ab, ebenso alles, was JARVIS heißt.
- **Öffentliches Repo:** keine Secrets, Chat-IDs, internen Adressen und keine Google-Ordner- oder Kalender-IDs.
  Konfiguration über Umgebungsvariablen (s. u.). Der Validator durchsucht alle Textdateien danach und prüft, dass kein
  Zeitplan ohne eigene Zeitzone läuft. Die GitHub Action läuft mit `contents: read` und ohne gespeicherte Zugangsdaten.

## KI-Budget (Schätzung!)

- Alle KI-Nodes nutzen **Gemini 2.5 Flash** (Free Tier).
- Vor **jedem** KI-Aufruf (Orchestrator, Loop, Engine Hub, Self-Builder mit 2 Aufrufen, Multi-Agent) steht derselbe
  Budget-Check. Er ist fail-closed: Ist die Datenbank nicht erreichbar, gibt es keinen KI-Aufruf.
- Jeder Aufruf wird in `llm_usage` mit **geschätzten** Kosten geloggt (Zeichen / 4 ≈ Token, Listenpreis). Beim Self-Builder ist auch die Länge der
  Prompt-Vorlagen geschätzt. Der Validator stellt sicher, dass vor jedem KI-Node (und zwischen zwei Aufrufen) ein Budget-Check
  steht und danach ein `llm_usage`-Eintrag folgt.
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
   - `EMMA_CORE_OS_URL`: Basis-URL von core-os (Pflicht)
   - optional: `EMMA_BUDGET_EUR` (Standard 5), `EMMA_DAILY_DOCS` (`on`/`off`), `EMMA_MAX_APPROVALS_PER_DAY` (Standard 5),
     `EMMA_QUIET_HOURS` (Standard `22-7`), `EMMA_MAX_WAKES_PER_DAY` (Standard 6), `EMMA_N8N_URL` (Standard: lokale n8n-Adresse,
     für das Anlegen freigegebener Workflows)
   - für Drive und Kalender: `EMMA_CALENDAR_ID`, `EMMA_DRIVE_FOLDER_NOTES`, `EMMA_DRIVE_FOLDER_DRAFTS`,
     `EMMA_DRIVE_FOLDER_BRIEFINGS`, `EMMA_DRIVE_FOLDER_LOG`. Fehlt ein Wert, schlägt genau diese Aktion fehl und wird als
     fehlgeschlagen protokolliert (nichts wird als erledigt verbucht).
   - Nötig ist außerdem, dass Code-Nodes auf Umgebungsvariablen zugreifen dürfen (`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`).
     Ohne diese Freigabe bricht jeder Lauf mit „EMMA_CORE_OS_URL ist nicht gesetzt“ ab. Die Alternative: den Wert im
     Node „Konfiguration“ direkt in n8n eintragen, aber nie zurück ins Repo.
2. **Datenbank:** `schema.sql` ausführen (idempotent, ergänzt auch die neue Spalte `approval_requested_at`).
3. **Credentials** in n8n anlegen und zuordnen: Gemini, Postgres, Google Calendar, Google Drive, **EMMA Webhook Auth**
   (Header Auth für eingehende Webhooks), **core-os API** (Header Auth für Aufrufe an core-os), Header Auth mit n8n-API-Key
   (nur Executor, zum Anlegen freigegebener Workflows).
4. **Sub-Workflows verknüpfen** in allen `Execute Workflow`-Nodes: `EMMA_ENGINE_HUB`, `EMMA_PROPOSE`,
   `EMMA_APPROVED_EXECUTOR`, `EMMA_WAKE_TIMER`, `EMMA_COGNITIVE_LOOP`.
5. **Erst wenn die core-os-Endpunkte bestätigt sind:** im Loop „Jetzt testen (Briefing)“ ausführen, danach aktivieren.

## Offene Punkte

- core-os-Endpunkte oben abgleichen oder in core-os ergänzen (Kontext, Freigabe anlegen, Ergebnis melden, Aufrufe nach n8n).
- core-os muss nach einer Freigabe `emma-approved` aufrufen (oder der Executor läuft nur um 07:00 und 21:30).
- Alte Tabellen `emma_memory`, `emma_tasks`, `emma_approvals`, `emma_agenda`, `interaction_memory` aus früheren
  Schema-Versionen: nach core-os übernehmen oder löschen. Das entscheidet der Nutzer, das Schema löscht nichts.
- Tagesreport von core-os (20:00) könnte `emma_artifacts` und `llm_usage` mit anzeigen. Dafür bräuchte core-os Lesezugriff.
- Verlangt core-os für Schreibzugriffe ein Token: im Credential „core-os API“ hinterlegen.

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
python3 tools/validate_workflows.py   # statische Regeln, siehe unten
python3 tools/test_validator.py       # beweist, dass der Validator 15 nachgebaute Fehler wirklich erkennt
node tools/test_code_nodes.js         # Logik der Code-Knoten ohne n8n (Freigabe-Filter, Allowlist, Rechte, Prompt-Schutz …)
```

Der Validator prüft: kaputte Verbindungen, doppelte Namen und Webhook-Pfade, Webhooks ohne Header-Auth oder Credential,
Telegram-Nodes und Telegram-Aufrufe, JARVIS, abgeschaltete Modelle, SQL-Injection-Muster, Zugriffe auf und Tabellen von core-os,
fehlende Budget-Checks vor KI-Aufrufen und fehlendes `llm_usage`-Logging, `onError=continue` ohne Protokoll dahinter,
fehlende Zeitzone bei Zeitplänen, fest eingetragene Google-IDs, abweichende oder zu weite Allowlists sowie in allen Textdateien
private IPs, Chat-IDs und Schlüsselmuster. Alles läuft auch automatisch als GitHub Action.

