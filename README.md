# EMMA / Metropolis – n8n Workflows

> **Status: GEBAUT, nicht LIVE.** Die Dateien sind geprüft (Validator, Syntax, Logik mit Testdaten), aber noch nicht
> in der produktiven n8n-Instanz (self-hosted, Ubuntu-VM auf der Synology, `100.79.103.114:5678`) ausgeführt worden.
> Der Telegram-Eingang des Orchestrators und der Herzschlag des Cognitive Loop sind **absichtlich deaktiviert**,
> bis die Fragen unter „Vor dem Aktivieren klären“ entschieden sind.

Früher waren es über 70 Workflows, viele davon doppelt, und die meisten liefen nicht. Jetzt sind es **8**:

| Workflow | Zweck |
|---|---|
| `EMMA_MASTER_ORCHESTRATOR` | Irina schreibt → Emma antwortet mit Gedächtnis, legt Termine an, ruft Engines oder Jarvis, versteht Befehle |
| `EMMA_COGNITIVE_LOOP` | **Emmas inneres Leben**: wacht selbst auf, denkt nach, plant, merkt sich Dinge, schreibt Irina |
| `EMMA_JARVIS` | **Jarvis**: analytischer Partner und zweite Meinung für Emma (und auf Wunsch für Irina direkt) |
| `EMMA_ENGINE_HUB` | **Eine** Engine mit allen Fach-Rollen (FINANCE, LEGAL, SALES, CONTENT, LEAD, …) statt 30 Kopien |
| `EMMA_DAILY_REPORT` | Tagesbericht 08:00 an Telegram |
| `METROPOLIS_DATA_GATEWAY` | Logs, Sync, KPIs, CRM-Leads in die DB (alte Webhook-Pfade bleiben gültig) |
| `METROPOLIS_MULTI_AGENT_CORE` | Strategie-, Risiko- und Opportunity-Agent parallel |
| `EMMA_SELF_BUILDER` | Baut neue Workflows mit Duplikat-Schutz und legt sie inaktiv an |

## Phase 1 – Entscheidungen

| Frage | Entscheidung | Umsetzung |
|---|---|---|
| Wo läuft es? | Synology mit Docker, PC als Reserve | n8n läuft bereits im Docker auf der Synology-VM. Alles hier sind n8n-Workflows, der PC wird nicht gebraucht. |
| Postfach | eigene Jarvis-Adresse, später | **Phase 2** (IMAP). In Phase 1 gibt es keine Mail-Anbindung. |
| Kanäle | Telegram zuerst | Nur Telegram aktiv. Vorschläge für später siehe unten. |
| Budget | 0 € jetzt, Verlustgrenze 5 € | Nur das Free-Tier-Modell **Gemini 2.5 Flash**. Jeder KI-Aufruf wird protokolliert. Ab **5 €** geschätzten Monatskosten macht Emma keine KI-Aufrufe mehr. |
| Autonomie | wie vorgeschlagen | Leitplanken bleiben: 6 Aktionen pro Zyklus, 3 Nachrichten pro Tag, Nachtruhe, riskante Aktionen nur mit Freigabe. |
| Erstes Ziel | Briefing und sichtbare Arbeitsspuren | Morgens ein Briefing-Dokument, abends ein Arbeitsprotokoll, Notizen, Entwürfe und Kalendereinträge. Alles steht im Daily Report mit Link. |
| Steuerberater | später | – |
| Schmerzpunkt | sehen, dass gearbeitet wird | Jede Spur landet in `emma_artifacts` und in Google Drive unter **Emma → EMMA_ARBEITSSPUREN**. |

### Wo die Arbeitsspuren landen (Google Drive → Emma → EMMA_ARBEITSSPUREN)

| Ordner | Inhalt | Wann |
|---|---|---|
| `01_Briefings` | „Briefing JJJJ-MM-TT“: Gedanken, Termine, Plan, offene Aufgaben, Themen | täglich 07:00 |
| `02_Wissen` | „Wissen – …“: Recherchen und Erkenntnisse (`write_note`) | wenn Emma etwas herausfindet |
| `03_Entwuerfe` | „Entwurf – …“: Texte, Posts, Angebote (`write_draft`), werden **nicht** verschickt | bei Bedarf |
| `04_Arbeitsprotokoll` | „Arbeitsprotokoll JJJJ-MM-TT“: jeder Denkzyklus mit Aktionen, erstellte Spuren, erledigte Aufgaben | täglich 21:30 |
| Kalender „EMMA“ | „🧠 EMMA: …“: Emmas eigene Weckzeiten | laufend |

Der Daily Report um 08:00 zeigt die Spuren der letzten 24 Stunden mit Link und den Budgetstand, z. B. „0,03 € von 5 €“.

### Kanäle: was noch fehlt (Vorschläge für später)

1. **E-Mail (IMAP/SMTP)** mit eigener Jarvis-Adresse: Mail-Sortierung, Entwürfe für Antworten (Phase 2)
2. **WhatsApp Business**: der Webhook `metropolis-whatsapp` ist schon da, es fehlt der Zugang über die Meta-API
3. **Google Kalender von Kunden, Buchungen aus dalino-app**: Termine automatisch ins Briefing
4. **Sprachnachrichten in Telegram**: Transkription (kostet Tokens, erst mit Budget-Erfahrung)
5. **Instagram/Facebook**: nur Entwürfe, Veröffentlichen immer mit Freigabe

## Emmas inneres Leben (`EMMA_COGNITIVE_LOOP`)

Emma prüft alle 15 Minuten, ob sie aufwachen soll:

- **07:00 Morgen-Routine**: Tag planen, Irina eine Morgennachricht schicken (Plan, Termine, Themen).
- **21:30 Abend-Reflexion** (früher `EMMA_DAILY_EVOLUTION`): Learnings festhalten, Erledigtes schließen, morgen planen.
- **Zu jedem Termin im Kalender „EMMA“**: Emma setzt sich dort selbst Weckzeiten (`🧠 EMMA: …`).
  Auch Irina kann dort einen Termin eintragen. Dann wacht Emma genau dann auf und liest Titel und Beschreibung als Auftrag.

Beim Aufwachen liest sie ihr Gedächtnis, offene Aufgaben, Freigaben, ihre Agenda, die Gespräche der letzten 24h,
den Austausch mit Jarvis und Irinas Termine. Dann entscheidet sie selbst, was sie tut:

| Aktion | Was passiert |
|---|---|
| `schedule_wake` | Termin im EMMA-Kalender → Emma wacht dann wieder auf |
| `create_task` / `complete_task` | Aufgaben verwalten |
| `add_agenda` | Thema, das sie mit Irina besprechen will (erscheint im Report, in `/agenda` und im nächsten Gespräch) |
| `remember` | Langzeitgedächtnis (Ziele, Entscheidungen, Strategien, Learnings, Personen, Vorlieben) |
| `message_irina` | Telegram-Nachricht an Irina |
| `write_note` / `write_draft` | Google-Doc in `02_Wissen` bzw. `03_Entwuerfe` (höchstens 3 pro Zyklus) |
| `run_engine` | Eine Fach-Engine arbeiten lassen |
| `ask_jarvis` | Jarvis um eine zweite Meinung bitten |
| `request_approval` | Um Freigabe bitten → Irina antwortet mit `/ok 12` oder `/nein 12` |

**Leitplanken:** Emma arbeitet frei, aber nicht grenzenlos.

- maximal 6 Aktionen pro Zyklus
- maximal 3 Nachrichten pro Tag, keine zwischen 22 und 7 Uhr
- höchstens 2 Engine-Läufe pro Zyklus
- Weckzeiten nur 10 Minuten bis 7 Tage im Voraus

Alles, was Geld kostet, nach außen geht, Kunden kontaktiert oder nicht rückgängig zu machen ist, läuft über `request_approval`.
Das entspricht dem früheren Council-500-Standard.

### Gedächtnis: Postgres → Google Drive

- Die Quelle ist Postgres (`emma_memory`, `emma_agenda`, `emma_cycles`, `agent_dialogue`, …).
- Nach jedem Denkzyklus schreibt Emma ihr komplettes Gedächtnis nach **Google Drive** in die bestehende
  `EMMA_memory.json` im EMMA-Ordner. Das Format ist wie bisher (`goals`, `decisions`, `strategies`, `learnings`, `tasks`, `conversations`, …),
  ergänzt um `agenda_mit_irina`, `jarvis_dialogue`, `last_thoughts` und `next_wake`.
- Für die Synology gibt es den deaktivierten Node „An Synology senden (optional)“. Er bekommt die Adresse, sobald
  feststeht, welches System dort das Gedächtnis führt (siehe unten).

## Jarvis (`EMMA_JARVIS`)

Jarvis ist Emmas analytischer Gegenpart: präzise, ehrlich, widerspricht, wenn etwas nicht stimmt.
Er **berät nur und handelt nicht selbst**. Emma entscheidet, Irina hat das letzte Wort.
Der Austausch wird in `agent_dialogue` gespeichert, und Emma sieht ihn beim nächsten Nachdenken.
Wichtige Hinweise von Jarvis landen in Emmas Gedächtnis.

- Emma fragt Jarvis selbst (`ask_jarvis`) oder leitet komplexe Fragen im Chat an ihn weiter.
- Optional kann Irina Jarvis direkt schreiben: Node `JARVIS_TELEGRAM_IN` aktivieren. Dafür braucht Jarvis einen **eigenen** Bot.
  Nur Irinas Chat-ID wird beantwortet.
- Der importierte Jarvis-Code auf der Synology (`jarvis_lab`, Status `QUARANTINED / READ_ONLY`) bleibt davon unberührt.
  Dieser n8n-Jarvis nutzt ihn nicht und hat keine Zugänge zu Secrets.

## Telegram

| Bot | n8n-Credential | Genutzt von |
|---|---|---|
| EMMA WORLDMASTER OS (@WorldMaster_Bot) | `telegram` | Orchestrator, Cognitive Loop, Daily Report |
| Jarvis (eigener Bot) | `telegram 2` | `EMMA_JARVIS` (Node ist bis zur Zuordnung deaktiviert) |
| Worldmaster Nor-Bot, Nova, Alpha_trade_bot | – | eigene Systeme, hier nicht verwendet |

Die Dateien `telegram.txt` und `telegram 2.txt` in „Emma Wichtig !“ sind leer. Das ist richtig so, Tokens gehören nur in
die n8n-Credentials. Prüfe beim Import, dass die Credential `telegram` wirklich @WorldMaster_Bot ist, z. B. in n8n mit „Test“.
Pro Bot darf nur **ein** Empfänger aktiv sein (siehe „Vor dem Aktivieren klären“).

**Befehle an Emma:** `/agenda` (Themen, Aufgaben, Freigaben) · `/ok 12` · `/nein 12` · `/erledigt 7`

## Vor dem Aktivieren klären

Laut `EMMA_ARCHITECTURE.md` und `N8N_WORKFLOW_KARTE.md` (Stand 14.–23.09.2026) gibt es schon mehrere Systeme,
die dasselbe tun wollen:

1. **Ein Haupteingang für @WorldMaster_Bot.** Schon heute lesen `emma-telegram-worker` (emma-core-os) und
   `EMMA_SUPERNOVA_METROPOLE_BACKOFFICE_V?` (`CEO_TELEGRAM_IN`) Telegram mit. Ein Bot kann aber nur **einen** Empfänger haben:
   Webhook und Polling schließen sich aus, zwei Empfänger bedeuten Doppelantworten oder verlorene Nachrichten.
   Erst entscheiden, wer antwortet. Danach `CEO_TELEGRAM_IN` hier nur aktivieren, wenn es dieser Orchestrator sein soll.
2. **Eine Wahrheit für Gedächtnis, Aufgaben und Freigaben.** emma-core-os hat eine eigene Postgres-Datenbank (Port 5434) mit Memory,
   Tasks und Approval-Gate. Die Tabellen in `schema.sql` dürfen keine zweite, abweichende Wahrheit werden. Entweder
   zeigt die Postgres-Credential in n8n auf **dieselbe** Datenbank wie core-os (Tabellen abgleichen), oder der Cognitive Loop
   ruft die core-os-API statt eigener Tabellen auf.
3. **Jarvis:** Laut `JARVIS_LAB_STATE.json` gibt es schon einen Jarvis als Mentor in core-os (nur lesend, unter Quarantäne).
   `EMMA_JARVIS` hier ist ein reiner n8n-Berater ohne eigene Aktionen. Entscheiden, ob beide gewollt sind oder ob Emma den core-os-Jarvis fragen soll.

## Einrichten

1. `schema.sql` in Postgres ausführen. Das Script ist idempotent, bestehende Daten bleiben erhalten.
2. Die 8 JSON-Dateien importieren und bei jedem Node die Credentials prüfen: Gemini, Postgres, `telegram`/`telegram 2`,
   Google Calendar, Google Drive und Header Auth mit `X-N8N-API-KEY` für die n8n-API.
3. In diesen Nodes den Ziel-Workflow auswählen:
   - Orchestrator: `EXECUTE_ENGINE` → `EMMA_ENGINE_HUB`, `EXECUTE_JARVIS` → `EMMA_JARVIS`
   - Cognitive Loop: `Engine ausführen` → `EMMA_ENGINE_HUB`, `Jarvis fragen` → `EMMA_JARVIS`
4. Alte Workflows erst deaktivieren und nach ein paar Tagen löschen (siehe unten).
5. Erst nach der Klärung oben: `CEO_TELEGRAM_IN` und „Herzschlag (15 min)“ aktivieren, dann die Workflows aktiv schalten.
   Engine Hub und Jarvis laufen als Sub-Workflows mit.

## Alte Workflows: was wo weiterlebt

Das stammt aus `ALL_WORKFLOWS_BACKUP.json` (Stand Mai, 75 Workflows). Live laufen laut `N8N_WORKFLOW_KARTE.md` (14.09.)
237 Workflows, davon 35 aktiv. Namen aus dem Backup gelten sinngemäß auch für die gleichnamigen Live-Workflows, aber:
**nichts löschen, was nicht in dieser Liste steht, und vorher in n8n exportieren.**

**Übernommen, danach löschen:**

| Alt | Lebt weiter in |
|---|---|
| alle `*_ENGINE_V700`, `*_ENGINE_V14`, `EMMA_C500_*_ENGINE_*`, `SUPERNOVA_ENGINE_*`, `EMMA_SUPERNOVA_V∞`, `METROPOLIS_DYNAMIC_ENGINE`, `INTELLIGENCE_SECURITY_V1000` | `EMMA_ENGINE_HUB` |
| `EMMA_DECISION_ENGINE` | `EMMA_JARVIS` |
| `METROPOLIS_MASTER_ORCHESTRATOR_*`, `EMMA_MASTER_ORCHESTRATOR_V2_ULTIMATE`, `EMMA_CLOUD_OS_V1/V2`, `EMMA_WORLDMASTER_SCO`, `EMMA_SUPERNOVA_MASTER_BRAIN` | `EMMA_MASTER_ORCHESTRATOR` |
| `EMMA_CALENDAR_SIMPLE`, `EMMA_CALENDAR_MANAGER_FIXED` | Orchestrator legt Termine direkt an (auch wiederkehrend) |
| `EMMA_DAILY_EVOLUTION` | Abend-Reflexion im `EMMA_COGNITIVE_LOOP` |
| `EMMA_MEMORY_ENGINE`, `EMMA_MEMORY_SYNC`, `EMMA_CONTEXT_ENGINE`, `VECTOR_MEMORY_ENGINE` | Gedächtnis in Loop und Orchestrator |
| `EMMA_COUNCIL_500_TEMPLATE` | Freigaben (`request_approval`, `/ok`, `/nein`) |
| `WF_02_Daily_Mayor_Briefing`, `WF_03_Hourly_Pulse_Check` | `EMMA_DAILY_REPORT` + Morgen-Routine |
| `EMMA_AGENT_HUB` | `METROPOLIS_MULTI_AGENT_CORE` |
| `CRM_ENGINE_V700_CLOUD`, `LOGGING_ENGINE`, `METROPOLIS_KPI_REGISTRY`, `METROPOLIS_V14_SYNC_BRIDGE` | `METROPOLIS_DATA_GATEWAY` |
| `EMMA_SELF_BUILDER_*`, `EMMA_WORKFLOW_CREATOR`, alle `EMMA_COGNITIVE_*` | `EMMA_SELF_BUILDER` |
| leere Hüllen: `LOCAL_AGENT_V2`, `pc_action_node…`, `My_Sub_Workflow_3`, `FINANZMOTOR_V700`, `EMMA_SUPERVISOR_V1` | hatten keine Funktion |

**Behalten, weil sie eine eigene Aufgabe haben** (von Duplikaten nur **eine** Kopie):

`SYNCHRONISIERE_SHOPIFY_MIT`, `TÄGLICHER_SALES_REPORT`, `ERSTELLE_EMAIL-AUTOMATION` (sieht aus wie der Sales-Report, bitte vergleichen),
`CONTENT_MEDIA_ENGINE`, `CONTENT_MEDIA_ADS_ENGINE`, `WF_11_Product_Listing_Factory`, `WF_15_Revenue_Discovery_Cluster`,
`WF_16_Conversion_Offer_Engine`, `WF_21_Email_Funnel_Automator`, `WF_22_Partnership_Affiliate_Scout`,
`EMMA_AI_BUSINESS_MASTER`, `EMMA_STATUS_REPORT_IMMO`, `EMMA_CALENDAR_QUICK_FIX` (ändert Termine),
`CRM_ENGINE_V700` (Google-Sheets-CRM), `EMMA_SKILLS_SH_DAILY_WATCHER`.
Achtung: `EMMA_C500_CORE_EMMA_SUPERNOVA_V_` (Telegram-Verkaufs-Funnel) hat einen eigenen Telegram-Trigger.
Er darf nicht am selben Bot hängen wie der Orchestrator.

**Google-Kalender:** Es gibt über 30 Kalender „EMMA | …“, einen pro altem Workflow, viele doppelt. Genutzt wird nur noch
der Kalender **„EMMA“**. Die anderen können weg, sobald die alten Workflows gelöscht sind.

## Prüfen

```bash
python3 tools/validate_workflows.py
```

Das Script prüft kaputte Verbindungen, doppelte Workflow-Namen und Webhook-Pfade, abgeschaltete Gemini-Modelle und
SQL mit direkt eingesetzten Werten. Es läuft auch automatisch als GitHub Action.
