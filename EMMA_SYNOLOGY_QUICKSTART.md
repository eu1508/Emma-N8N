# EMMA + Synology + n8n Quickstart

## 1) SSH + n8n prüfen

```bash
export SYNOLOGY_SSH_HOST="DEIN_SYNOLOGY_HOST"
export SYNOLOGY_SSH_USER="administrator"   # oder codex
export SYNOLOGY_SSH_PORT="22"
export N8N_BASE_URL="http://127.0.0.1:5678"
export N8N_API_KEY="DEIN_N8N_KEY"

./check_synology_n8n_remote.sh
```

## 2) EMMA Workflows deployen (und aktivieren)

```bash
export ACTIVATE_ON_DEPLOY="true"
./deploy_emma_n8n_ssh.sh
```

## 2b) One-shot Live-Fix (alles in einem Lauf)

```bash
export N8N_BASE_URL="http://DEIN-N8N-HOST:5678"
export N8N_API_KEY="DEIN_N8N_KEY"
export AUTO_REPAIR_BRIEFING="true"   # optional
./run_emma_n8n_live_fix.sh
```

Das Script führt automatisch aus: Validate -> Deploy -> Diagnose -> Briefing-Repair (Dry-Run + optional Apply).

## 3) Alle lokalen Workflows validieren (vor Deploy)

```bash
./validate_all_n8n_workflows.sh
```

Optional mit API-Abgleich als harte Prüfung:
```bash
STRICT_API=true ./validate_all_n8n_workflows.sh
```

## 4) Laufzeit-Diagnose ziehen

```bash
./diagnose_emma_n8n.sh
```

## 5) MORNING BRIEFING Fehler (stündlich statt täglich) reparieren

Dein Log zeigt stündliche Briefings am 17.04.2026 (00:00, 01:00, 02:00, ...). Das ist fast sicher ein falscher Schedule-Trigger.

### Erst prüfen (Dry-Run, ohne Änderung)
```bash
DRY_RUN=true ./repair_emma_briefing_schedule.sh
```

### Dann wirklich patchen (täglich 08:00 Europe/Berlin)
```bash
DRY_RUN=false TARGET_TZ="Europe/Berlin" TARGET_HOUR="8" TARGET_MINUTE="0" ./repair_emma_briefing_schedule.sh
```

## 6) API-Bridge testen

```bash
curl -sS -X POST "$N8N_BASE_URL/webhook/emma-n8n-api-bridge" \
  -H 'Content-Type: application/json' \
  -d '{"action":"health"}' | jq .

curl -sS -X POST "$N8N_BASE_URL/webhook/emma-n8n-api-bridge" \
  -H 'Content-Type: application/json' \
  -d '{"action":"help"}' | jq .
```

## 7) Telegram: warum EMMA „kein Internet/Bilder“ sagt

Wenn EMMA das sagt, ist es **kein Modellfehler**, sondern Routing/Tooling:

1. Telegram-Command (`/status`, `/health`, `/diag`) muss auf Bridge-Action gemappt sein.
2. Für Internet echte HTTP Request Nodes verbinden.
3. Für Bildlesen OCR/Vision Node verbinden.
4. Erst dann darf EMMA im Prompt behaupten, dass sie Internet/Bilder kann.

Ohne diese Nodes ist die Antwort „kein direkter Zugriff“ technisch korrekt.
