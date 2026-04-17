#!/usr/bin/env bash
set -euo pipefail

SYNOLOGY_SSH_HOST="${SYNOLOGY_SSH_HOST:-}"
SYNOLOGY_SSH_USER="${SYNOLOGY_SSH_USER:-administrator}"
SYNOLOGY_SSH_PORT="${SYNOLOGY_SSH_PORT:-22}"
SYNOLOGY_SSH_KEY="${SYNOLOGY_SSH_KEY:-}"

N8N_BASE_URL="${N8N_BASE_URL:-http://127.0.0.1:5678}"
N8N_API_KEY="${N8N_API_KEY:-}"

if [[ -z "$SYNOLOGY_SSH_HOST" ]]; then
  echo "ERROR: SYNOLOGY_SSH_HOST fehlt (z. B. 192.168.178.50)."
  exit 1
fi

if [[ -z "$N8N_API_KEY" ]]; then
  echo "ERROR: N8N_API_KEY fehlt."
  exit 2
fi

SSH_OPTS=(-p "$SYNOLOGY_SSH_PORT" -o StrictHostKeyChecking=accept-new)
SCP_OPTS=(-P "$SYNOLOGY_SSH_PORT" -o StrictHostKeyChecking=accept-new)
if [[ -n "$SYNOLOGY_SSH_KEY" ]]; then
  SSH_OPTS+=( -i "$SYNOLOGY_SSH_KEY" )
  SCP_OPTS+=( -i "$SYNOLOGY_SSH_KEY" )
fi

REMOTE="$SYNOLOGY_SSH_USER@$SYNOLOGY_SSH_HOST"
REMOTE_DIR="/tmp/emma_n8n_deploy_$(date +%s)"

mapfile -t WORKFLOW_FILES < <(rg --files | rg '\.json$' | sort)
FILES=(
  "deploy_emma_n8n.sh"
  "diagnose_emma_n8n.sh"
  "repair_emma_briefing_schedule.sh"
  "validate_all_n8n_workflows.sh"
  "${WORKFLOW_FILES[@]}"
)

echo "== SSH Verbindung prüfen =="
ssh "${SSH_OPTS[@]}" "$REMOTE" "echo Connected to \\$(hostname) as \\$(whoami)"

echo "== Remote Verzeichnis anlegen: $REMOTE_DIR =="
ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$REMOTE_DIR'"

echo "== Dateien hochladen =="
scp "${SCP_OPTS[@]}" "${FILES[@]}" "$REMOTE:$REMOTE_DIR/"

echo "== Remote Deploy starten =="
ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$REMOTE_DIR' && chmod +x deploy_emma_n8n.sh && N8N_BASE_URL='$N8N_BASE_URL' N8N_API_KEY='$N8N_API_KEY' ./deploy_emma_n8n.sh"

echo "== Fertig: Workflows via SSH auf Synology deployt =="
