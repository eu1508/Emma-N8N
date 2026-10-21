#!/usr/bin/env bash
# FreeLLMAPI ohne Docker installieren und starten (Node.js 20+ nötig).
#
# Gedacht für das "Setup script" der Claude-Code-Cloud-Umgebung: Inhalt dieser
# Datei dort einfügen, dann ist FreeLLMAPI in JEDEM neuen Chat dieser Umgebung
# unter http://127.0.0.1:3001/v1 verfügbar. Funktioniert auch auf jedem
# Linux/macOS-Rechner ohne Docker.
#
# Anbieter-Keys kommen aus Umgebungsvariablen (in der Umgebung als Secrets
# hinterlegen, nie ins Repo schreiben):
#   GEMINI_API_KEY  GROQ_API_KEY  OPENROUTER_API_KEY  MISTRAL_API_KEY
#   CEREBRAS_API_KEY  NVIDIA_API_KEY  COHERE_API_KEY  HF_TOKEN
# Optional: FREELLMAPI_ADMIN_EMAIL / FREELLMAPI_ADMIN_PASSWORD (Dashboard-Login)
#
# Danach:  Basis-URL  http://127.0.0.1:3001/v1
#          API-Key    steht in ~/.freellm/unified-key
set -euo pipefail

FREELLM_HOME="${FREELLM_HOME:-$HOME/.freellm}"
APP="$FREELLM_HOME/freellmapi"
PORT="${FREELLMAPI_PORT:-3001}"
log() { printf '[freellm] %s\n' "$*"; }

command -v node >/dev/null || { log "Node.js fehlt – bitte Node 20+ installieren."; exit 1; }
mkdir -p "$FREELLM_HOME"

# 1) Code holen bzw. aktualisieren und bauen
if [ -d "$APP/.git" ]; then
  git -C "$APP" pull -q --ff-only || log "Update übersprungen (offline?)"
else
  git clone -q --depth 1 https://github.com/tashfeenahmed/freellmapi.git "$APP"
fi
cd "$APP"
if [ ! -f server/dist/index.js ] || [ package-lock.json -nt server/dist/index.js ] || [ "$(git rev-parse HEAD)" != "$(cat .built-rev 2>/dev/null)" ]; then
  log "Installiere Abhängigkeiten und baue (dauert 1–2 Minuten) ..."
  npm ci --no-audit --no-fund --loglevel=error
  npm run build >"$FREELLM_HOME/build.log" 2>&1 || { log "Build fehlgeschlagen, siehe $FREELLM_HOME/build.log"; exit 1; }
  git rev-parse HEAD > .built-rev
fi

# 2) .env schreiben (Verschlüsselungsschlüssel bleibt erhalten)
KEY_FILE="$FREELLM_HOME/encryption-key"
[ -f "$KEY_FILE" ] || { node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))' > "$KEY_FILE"; chmod 600 "$KEY_FILE"; }
CFG="$(node -e '
const m={GEMINI_API_KEY:"google",GROQ_API_KEY:"groq",OPENROUTER_API_KEY:"openrouter",MISTRAL_API_KEY:"mistral",
  CEREBRAS_API_KEY:"cerebras",NVIDIA_API_KEY:"nvidia",COHERE_API_KEY:"cohere",HF_TOKEN:"huggingface"};
const c={}; const keys=Object.entries(m).filter(([v])=>process.env[v]).map(([v,p])=>({platform:p,key:process.env[v],label:"env"}));
if(keys.length) c.keys=keys;
if(process.env.FREELLMAPI_ADMIN_EMAIL&&process.env.FREELLMAPI_ADMIN_PASSWORD) c.admin={email:process.env.FREELLMAPI_ADMIN_EMAIL,password:process.env.FREELLMAPI_ADMIN_PASSWORD};
process.stdout.write(Object.keys(c).length?JSON.stringify(c):"");')"
{
  echo "ENCRYPTION_KEY=$(cat "$KEY_FILE")"
  echo "PORT=$PORT"
  echo "HOST=127.0.0.1"
  echo "REQUEST_ANALYTICS_RETENTION_DAYS=90"
  echo "REQUEST_ANALYTICS_MAX_ROWS=100000"
  if [ -n "$CFG" ]; then echo "FREEAPI_CONFIG_JSON=$CFG"; fi
} > .env
chmod 600 .env

# 3) Starten (falls nicht schon läuft)
if curl -fsS "http://127.0.0.1:$PORT/api/ping" >/dev/null 2>&1; then
  log "FreeLLMAPI läuft bereits."
else
  NODE_ENV=production nohup node server/dist/index.js > "$FREELLM_HOME/freellmapi.log" 2>&1 &
  for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:$PORT/api/ping" >/dev/null 2>&1 && break; sleep 1; done
fi
curl -fsS "http://127.0.0.1:$PORT/api/ping" >/dev/null || { log "Start fehlgeschlagen, siehe $FREELLM_HOME/freellmapi.log"; exit 1; }

# 4) Unified API Key auslesen und ablegen
node -e '
const Database=require(process.argv[1]+"/node_modules/better-sqlite3");
const db=new Database(process.argv[1]+"/server/data/freeapi.db",{readonly:true});
process.stdout.write(db.prepare("SELECT value FROM settings WHERE key = ?").get("unified_api_key").value);' "$APP" > "$FREELLM_HOME/unified-key"
chmod 600 "$FREELLM_HOME/unified-key"

log "FreeLLMAPI bereit: http://127.0.0.1:$PORT/v1  (Key: $FREELLM_HOME/unified-key)"
