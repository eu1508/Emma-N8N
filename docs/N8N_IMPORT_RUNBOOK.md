# n8n Import & Binding Runbook

## Warum ich es nicht direkt in deiner n8n-Cloud einbinden kann

Ich kann lokale JSON-Dateien bearbeiten und validieren. In deine laufende n8n-Instanz kann ich aber nur schreiben, wenn diese Daten vorhanden sind:

- `N8N_BASE_URL`, zum Beispiel `https://dalino.app.n8n.cloud`
- `N8N_API_KEY` mit Workflow-Rechten
- Zugriff auf die n8n Public API; laut n8n-Dokumentation ist die Public API im Free Trial nicht verfügbar
- bestehende Credentials in n8n: Gemini, Telegram, SQLite/Postgres usw.

Ohne diese Werte hätte ein automatischer Import keinen autorisierten Zielserver und wäre unsicher.

## Was du jetzt konkret machen sollst

1. Falls Keys irgendwo gepostet wurden: zuerst rotieren/löschen. Nie echte Secrets in Chat oder Git verwenden.
2. Öffne n8n und erstelle einen neuen API-Key.
3. Kopiere `.env.n8n.example` zu `.env.n8n`.
4. Trage in `.env.n8n` deine echte `N8N_BASE_URL` und deinen neuen echten `N8N_API_KEY` ein.
5. Starte zuerst Secret-Scan und Dry-run.
6. Wenn der Dry-run die Workflows findet, starte `--apply`.
7. Prüfe danach in n8n die Credentials und aktiviere erst dann mit `--activate`.

## Automatischer Import per API

Dry-run:

```bash
./install_in_n8n.sh check
```

Oder direkt:

```bash
python3 tools/deploy_n8n_bundle.py
```

Live-Bindung mit `.env.n8n`:

```bash
cp .env.n8n.example .env.n8n
# .env.n8n bearbeiten und echten API-Key eintragen
./install_in_n8n.sh deploy
```

Alternative ohne Datei:

```bash
export N8N_BASE_URL="https://dalino.app.n8n.cloud"
export N8N_API_KEY="n8n_api_..."
python3 tools/deploy_n8n_bundle.py --apply
```

Optional mit Aktivierung:

```bash
./install_in_n8n.sh activate
```

## Was das Script macht

1. Liest alle Workflow-JSON-Dateien im Repo.
2. Erstellt oder aktualisiert alle Sub-Workflows vor dem Master-Orchestrator.
3. Ermittelt die echten Workflow-IDs aus der n8n-Instanz.
4. Patcht `EXECUTE_ENGINE` im Master-Orchestrator so die Skill-Routen auf die echten n8n-IDs zeigen.
5. Setzt `METROPOLIS_ERROR_GUARDIAN` als Error Workflow in den Workflow-Settings, soweit die API dies akzeptiert.
6. Aktiviert Workflows nur, wenn `--activate` gesetzt ist.

## Nach dem Import in der n8n UI prüfen

- Öffne `METROPOLIS_MASTER_ORCHESTRATOR_V14` und prüfe `EXECUTE_ENGINE`.
- Öffne `METROPOLIS_ERROR_GUARDIAN` und aktiviere ihn als Error Workflow, falls die API-Einstellung nicht übernommen wurde.
- Öffne `METROPOLIS_OPERATIONS_ENGINE` und teste mit:

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

## Offizielle n8n-Hinweise

- n8n Public API kann Workflows programmatisch verwalten.
- n8n CLI kann ebenfalls Workflows per API erstellen, ist aber laut Dokumentation Beta.
- Workflow Settings enthalten unter anderem Error Workflow und Estimated time saved.
