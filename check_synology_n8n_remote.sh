#!/usr/bin/env bash
set -euo pipefail

SYNOLOGY_SSH_HOST="${SYNOLOGY_SSH_HOST:-}"
SYNOLOGY_SSH_USER="${SYNOLOGY_SSH_USER:-administrator}"
SYNOLOGY_SSH_PORT="${SYNOLOGY_SSH_PORT:-22}"
SYNOLOGY_SSH_KEY="${SYNOLOGY_SSH_KEY:-}"
N8N_BASE_URL="${N8N_BASE_URL:-http://127.0.0.1:5678}"
N8N_API_KEY="${N8N_API_KEY:-}"

if [[ -z "$SYNOLOGY_SSH_HOST" ]]; then
  echo "ERROR: SYNOLOGY_SSH_HOST fehlt."
  exit 1
fi

SSH_OPTS=(-p "$SYNOLOGY_SSH_PORT" -o StrictHostKeyChecking=accept-new)
if [[ -n "$SYNOLOGY_SSH_KEY" ]]; then
  SSH_OPTS+=( -i "$SYNOLOGY_SSH_KEY" )
fi

REMOTE="$SYNOLOGY_SSH_USER@$SYNOLOGY_SSH_HOST"

echo "== [1/5] SSH Login prüfen =="
ssh "${SSH_OPTS[@]}" "$REMOTE" "echo 'OK SSH:' \\$(hostname) user=\\$(whoami)"

echo "== [2/5] Remote Tools prüfen (bash/curl/jq) =="
ssh "${SSH_OPTS[@]}" "$REMOTE" '
  for bin in bash curl jq; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "OK $bin: $(command -v "$bin")"
    else
      echo "MISSING $bin"
    fi
  done
'

echo "== [3/5] n8n Health prüfen =="
ssh "${SSH_OPTS[@]}" "$REMOTE" "
  code=\\$(curl -sS -m 8 -o /tmp/n8n_remote_health.json -w '%{http_code}' '$N8N_BASE_URL/rest/health' || true)
  echo 'rest/health ->' \\$code
  if [[ ! \\$code =~ ^2 ]]; then
    code2=\\$(curl -sS -m 8 -o /tmp/n8n_remote_health2.json -w '%{http_code}' '$N8N_BASE_URL/healthz' || true)
    echo 'healthz ->' \\$code2
  fi
"

if [[ -n "$N8N_API_KEY" ]]; then
  echo "== [4/5] n8n API Auth prüfen =="
  ssh "${SSH_OPTS[@]}" "$REMOTE" "
    code=\\$(curl -sS -m 10 -o /tmp/n8n_remote_auth.json -w '%{http_code}' -H 'X-N8N-API-KEY: $N8N_API_KEY' '$N8N_BASE_URL/api/v1/workflows?limit=1' || true)
    echo 'api auth ->' \\$code
    if [[ ! \\$code =~ ^2 ]]; then
      echo 'auth response:'
      cat /tmp/n8n_remote_auth.json || true
    fi
  "
else
  echo "== [4/5] n8n API Auth übersprungen (kein N8N_API_KEY) =="
fi

echo "== [5/5] Empfehlung =="
echo "Wenn oben nur OK-Status steht, dann danach ausführen:"
echo "  ./deploy_emma_n8n_ssh.sh"
