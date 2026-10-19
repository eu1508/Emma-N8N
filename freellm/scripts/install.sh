#!/usr/bin/env bash
# FreeLLM-Installer für Emma-N8N
#
#   ./install.sh            startet beides (FreeLLM-Proxy + FreeLLMAPI)
#   ./install.sh proxy      nur FreeLLM-Proxy  (Projekt 1, http://localhost:3000)
#   ./install.sh api        nur FreeLLMAPI     (Projekt 2, http://localhost:3001)
#   ./install.sh native     FreeLLMAPI ohne Docker (Node.js), z.B. für Claude-Cloud
#   ./install.sh status     zeigt laufende Container
#   ./install.sh stop       stoppt alles
#
# API-Keys werden aus Umgebungsvariablen gelesen (nie ins Repo schreiben!):
#   GEMINI_API_KEY  GROQ_API_KEY  OPENROUTER_API_KEY  MISTRAL_API_KEY
#   CEREBRAS_API_KEY  NVIDIA_API_KEY  COHERE_API_KEY  HF_TOKEN
# Optional für FreeLLMAPI (legt das Dashboard-Konto automatisch an):
#   FREELLMAPI_ADMIN_EMAIL  FREELLMAPI_ADMIN_PASSWORD
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXY_DIR="$BASE/freellm-proxy"
API_DIR="$BASE/freellmapi"
MODE="${1:-all}"

log() { printf '\033[1;36m[freellm]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[freellm]\033[0m %s\n' "$*" >&2; exit 1; }

rand_hex() { openssl rand -hex "$1" 2>/dev/null || head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# Setzt KEY=VALUE in einer .env-Datei (ersetzt vorhandene Zeile oder hängt an).
set_kv() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  grep -v -E "^#?\s*${key}=" "$file" > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# Ersetzt einen Platzhalter nur, wenn er noch nicht gesetzt wurde.
fill_placeholder() {
  local file="$1" key="$2" value="$3"
  if grep -q -E "^${key}=(your_|your-|\"?$)" "$file"; then set_kv "$file" "$key" "$value"; fi
}

ensure_docker() {
  command -v docker >/dev/null || die "Docker ist nicht installiert: https://docs.docker.com/get-docker/"
  if ! docker info >/dev/null 2>&1; then
    if command -v dockerd >/dev/null && [ "$(id -u)" = 0 ]; then
      log "Docker-Daemon läuft nicht – starte dockerd ..."
      (dockerd >/tmp/dockerd.log 2>&1 &)
      for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
    fi
    docker info >/dev/null 2>&1 || die "Docker-Daemon nicht erreichbar (Docker Desktop starten bzw. 'sudo systemctl start docker')."
  fi
  docker compose version >/dev/null 2>&1 || die "'docker compose' fehlt (Docker Compose v2 installieren)."
}

setup_proxy() {
  local env="$PROXY_DIR/.env"
  [ -f "$env" ] || { cp "$PROXY_DIR/.env.example" "$env"; chmod 600 "$env"; log "Neue $env angelegt"; }
  fill_placeholder "$env" LITELLM_SALT_KEY   "sk-$(rand_hex 24)"
  fill_placeholder "$env" LITELLM_MASTER_KEY "sk-$(rand_hex 24)"
  fill_placeholder "$env" LITELLM_DB_PASSWORD "$(rand_hex 16)"
  fill_placeholder "$env" FREELLM_DB_PASSWORD "$(rand_hex 16)"
  [ -n "${GEMINI_API_KEY:-}" ] && set_kv "$env" GEMINI_API_KEY "$GEMINI_API_KEY"
  [ -n "${GROQ_API_KEY:-}" ]   && set_kv "$env" GROQ_API_KEY "$GROQ_API_KEY"
  if grep -q -E '^(GEMINI|GROQ)_API_KEY=your_' "$env"; then
    log "Hinweis: GEMINI_API_KEY und/oder GROQ_API_KEY fehlen noch in $env"
  fi
  log "Starte FreeLLM-Proxy (Projekt 1) ..."
  docker compose -f "$PROXY_DIR/docker-compose.yml" --project-directory "$PROXY_DIR" up -d
  log "FreeLLM-Proxy: http://localhost:3000/v1  (OpenAI-kompatibel)"
}

setup_api() {
  local env="$API_DIR/.env"
  [ -f "$env" ] || { cp "$API_DIR/.env.example" "$env"; chmod 600 "$env"; log "Neue $env angelegt"; }
  fill_placeholder "$env" ENCRYPTION_KEY "$(rand_hex 32)"

  # Anbieter-Keys + Admin-Konto aus Umgebungsvariablen als Startkonfiguration übergeben.
  local cfg
  cfg="$(python3 - <<'PY'
import json, os
mapping = {
    "GEMINI_API_KEY": "google", "GROQ_API_KEY": "groq", "OPENROUTER_API_KEY": "openrouter",
    "MISTRAL_API_KEY": "mistral", "CEREBRAS_API_KEY": "cerebras", "NVIDIA_API_KEY": "nvidia",
    "COHERE_API_KEY": "cohere", "HF_TOKEN": "huggingface",
}
cfg = {}
keys = [{"platform": p, "key": os.environ[v], "label": "env"} for v, p in mapping.items() if os.environ.get(v)]
if keys:
    cfg["keys"] = keys
email, pw = os.environ.get("FREELLMAPI_ADMIN_EMAIL"), os.environ.get("FREELLMAPI_ADMIN_PASSWORD")
if email and pw:
    cfg["admin"] = {"email": email, "password": pw}
print(json.dumps(cfg, separators=(",", ":")) if cfg else "")
PY
)"
  [ -n "$cfg" ] && set_kv "$env" FREEAPI_CONFIG_JSON "$cfg"

  log "Starte FreeLLMAPI (Projekt 2) ..."
  docker compose -f "$API_DIR/docker-compose.yml" --project-directory "$API_DIR" up -d
  log "FreeLLMAPI: Dashboard http://localhost:3001  |  API http://localhost:3001/v1"
  log "Den 'Unified API Key' findest du im Dashboard unter 'Keys'."
}

case "$MODE" in
  all)    ensure_docker; setup_proxy; setup_api ;;
  proxy)  ensure_docker; setup_proxy ;;
  api)    ensure_docker; setup_api ;;
  native) bash "$BASE/scripts/cloud-setup.sh" ;;
  status) docker ps --filter name=freellm ;;
  stop)
    docker compose -f "$PROXY_DIR/docker-compose.yml" --project-directory "$PROXY_DIR" down || true
    docker compose -f "$API_DIR/docker-compose.yml" --project-directory "$API_DIR" down || true ;;
  *) die "Unbekannter Modus '$MODE' (all | proxy | api | native | status | stop)" ;;
esac
