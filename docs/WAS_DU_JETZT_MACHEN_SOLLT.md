# Was du jetzt machen sollst

Du musst nicht weiter raten. Das ist der konkrete Ablauf:

## 1. API-Key in n8n holen

Öffne deine n8n-Instanz und erstelle einen API-Key mit Workflow-Rechten. Ohne diesen Key kann kein Tool sicher in deine Cloud schreiben.

## 2. `.env.n8n` anlegen

```bash
cp .env.n8n.example .env.n8n
```

Dann `.env.n8n` öffnen und ausfüllen:

```bash
N8N_BASE_URL=https://dalino.app.n8n.cloud
N8N_API_KEY=n8n_api_DEIN_ECHTER_KEY
```

## 3. Erst Dry-run ausführen

```bash
python3 tools/deploy_n8n_bundle.py
```

Wenn hier 36 Workflows angezeigt werden, ist das Bundle lokal bereit.

## 4. In n8n importieren / binden

```bash
python3 tools/deploy_n8n_bundle.py --apply
```

Das Script erstellt oder aktualisiert die Workflows und patcht den Master-Orchestrator auf die echten n8n-Workflow-IDs.

## 5. Credentials in n8n prüfen

In n8n prüfen:

- `Google Gemini API`
- `Telegram Metropolis`
- `Metropolis SQLite`
- Postgres-Credentials, falls du Postgres-Workflows aktiv nutzt

## 6. Error Workflow setzen

Prüfe in n8n, ob `METROPOLIS_ERROR_GUARDIAN` als Error Workflow gesetzt ist. Falls nicht, manuell in den Workflow Settings setzen.

## 7. Testlauf machen

Teste `METROPOLIS_OPERATIONS_ENGINE` mit:

```json
{
  "text": "health savings report",
  "runs": 20,
  "manual_minutes": 30,
  "automation_minutes": 3,
  "hourly_rate_eur": 75,
  "avoided_outage_minutes": 60
}
```

## 8. Erst danach aktivieren

Wenn die Tests erfolgreich sind:

```bash
python3 tools/deploy_n8n_bundle.py --apply --activate
```

## Wenn etwas schiefgeht

- Kein API-Key: n8n kann nicht automatisch beschrieben werden.
- Free Trial ohne Public API: manueller Import in der n8n UI nötig.
- Credentials fehlen: Workflows importieren, aber externe Aktionen schlagen fehl, bis Credentials verbunden sind.
