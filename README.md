# EMMA / Metropolis – n8n Workflows

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

### Gedächtnis: Postgres → Google Drive → Synology

- Die Quelle ist Postgres (`emma_memory`, `emma_agenda`, `emma_cycles`, `agent_dialogue`, …).
- Nach jedem Denkzyklus schreibt Emma ihr komplettes Gedächtnis nach **Google Drive** in die bestehende
  `EMMA_memory.json` im EMMA-Ordner. Das Format ist wie bisher (`goals`, `decisions`, `strategies`, `learnings`, `tasks`, `conversations`, …),
  ergänzt um `agenda_mit_irina`, `jarvis_dialogue`, `last_thoughts` und `next_wake`.
- **Synology:** n8n läuft in der Cloud (`dalino.app.n8n.cloud`) und kommt nicht direkt ins Heimnetz (`192.168.178.x`).
  Deshalb auf der Synology **Cloud Sync** für den Google-Drive-Ordner einrichten, dann liegt das Gedächtnis automatisch auch dort.
  Alternativ gibt es den Node „An Synology senden (optional)“. Er ist deaktiviert und braucht eine von außen erreichbare Adresse.

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
| EMMA WORLDMASTER OS | `telegram` | Orchestrator, Cognitive Loop, Daily Report |
| Jarvis (eigener Bot) | `telegram 2` | `EMMA_JARVIS` (Node ist bis zur Zuordnung deaktiviert) |
| Worldmaster Nor-Bot, Nova, Alpha_trade_bot | – | eigene Systeme, hier nicht verwendet |

Prüfe beim Import, dass `telegram` wirklich der Token von **EMMA WORLDMASTER OS** ist, z. B. in n8n mit „Test“ oder über
`https://api.telegram.org/bot<TOKEN>/getMe`. Pro Bot darf nur **ein** aktiver Workflow einen Telegram-Trigger haben.

**Befehle an Emma:** `/agenda` (Themen, Aufgaben, Freigaben) · `/ok 12` · `/nein 12` · `/erledigt 7`

## Einrichten

1. `schema.sql` in Postgres ausführen. Das Script ist idempotent, bestehende Daten bleiben erhalten.
2. Die 8 JSON-Dateien importieren und bei jedem Node die Credentials prüfen: Gemini, Postgres, `telegram`/`telegram 2`,
   Google Calendar, Google Drive und Header Auth mit `X-N8N-API-KEY` für die n8n-API.
3. In diesen Nodes den Ziel-Workflow auswählen:
   - Orchestrator: `EXECUTE_ENGINE` → `EMMA_ENGINE_HUB`, `EXECUTE_JARVIS` → `EMMA_JARVIS`
   - Cognitive Loop: `Engine ausführen` → `EMMA_ENGINE_HUB`, `Jarvis fragen` → `EMMA_JARVIS`
4. Alte Workflows erst deaktivieren und nach ein paar Tagen löschen (siehe unten).
5. Aktivieren: Orchestrator, Cognitive Loop, Daily Report, Data Gateway (Engine Hub und Jarvis laufen als Sub-Workflows mit).

## Alte Workflows: was wo weiterlebt

Das stammt aus `ALL_WORKFLOWS_BACKUP.json` (Stand Mai). Was dort nicht auftaucht, bitte vor dem Löschen kurz prüfen.

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
