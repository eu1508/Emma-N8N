#!/usr/bin/env bash
set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
N8N_API_URL="${N8N_API_URL:-$N8N_BASE_URL/api/v1}"
N8N_API_KEY="${N8N_API_KEY:-}"
ACTIVATE_ON_DEPLOY="${ACTIVATE_ON_DEPLOY:-true}"
ACTIVE_EXCLUDE_REGEX="${ACTIVE_EXCLUDE_REGEX:-^$}"
JSON_GLOB_REGEX="${JSON_GLOB_REGEX:-\.json$}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -z "$N8N_API_KEY" ]]; then
  echo "ERROR: N8N_API_KEY ist leer. Bitte setzen und erneut starten."
  exit 1
fi

check_endpoint() {
  local url="$1"
  local code
  code=$(curl -sS -m 8 -o "$TMP_DIR/health.json" -w '%{http_code}' "$url" || true)
  echo "Health check $url -> HTTP $code"
  [[ "$code" =~ ^2 ]]
}

api_call() {
  local method="$1"; shift
  local url="$1"; shift
  local output_file="$1"; shift
  local code

  code=$(curl -sS -m 30 -o "$output_file" -w '%{http_code}' \
    -X "$method" "$url" \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$@" || true)

  echo "$code"
}

is_workflow_json() {
  local file="$1"
  jq -e 'has("name") and has("nodes") and has("connections") and (.nodes|type=="array") and (.connections|type=="object")' "$file" >/dev/null 2>&1
}

echo "== Prüfe n8n Erreichbarkeit =="
if ! check_endpoint "$N8N_BASE_URL/rest/health"; then
  check_endpoint "$N8N_BASE_URL/healthz" || {
    echo "ERROR: n8n nicht erreichbar unter $N8N_BASE_URL"
    exit 2
  }
fi

echo "== Prüfe API Key =="
auth_code=$(curl -sS -m 10 -o "$TMP_DIR/auth.json" -w '%{http_code}' \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_API_URL/workflows?limit=1" || true)
if [[ ! "$auth_code" =~ ^2 ]]; then
  echo "ERROR: API Auth fehlgeschlagen (HTTP $auth_code)."
  cat "$TMP_DIR/auth.json" || true
  exit 3
fi

mapfile -t CANDIDATE_FILES < <(rg --files | rg "$JSON_GLOB_REGEX" | sort)
WORKFLOWS=()
for f in "${CANDIDATE_FILES[@]}"; do
  if [[ -f "$f" ]] && is_workflow_json "$f"; then
    WORKFLOWS+=("$f")
  fi
done

if (( ${#WORKFLOWS[@]} == 0 )); then
  echo "ERROR: Keine gültigen Workflow-JSON-Dateien gefunden."
  exit 4
fi

echo "== Gefundene Workflow-Dateien: ${#WORKFLOWS[@]} =="

existing_file="$TMP_DIR/workflows.json"
code=$(curl -sS -m 20 -o "$existing_file" -w '%{http_code}' \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_API_URL/workflows?limit=500" || true)
if [[ ! "$code" =~ ^2 ]]; then
  echo "ERROR: Konnte vorhandene Workflows nicht laden (HTTP $code)"
  cat "$existing_file" || true
  exit 5
fi

failures=0
created=0
updated=0
activated=0
skipped_activate=0

for wf in "${WORKFLOWS[@]}"; do
  name=$(jq -r '.name // empty' "$wf")
  has_nodes=$(jq '(.nodes | type=="array") and (.nodes|length>0)' "$wf")
  has_connections=$(jq '.connections | type=="object"' "$wf")

  if [[ -z "$name" || "$has_nodes" != "true" || "$has_connections" != "true" ]]; then
    echo "FAIL: Ungültige Workflow-Datei: $wf"
    failures=$((failures + 1))
    continue
  fi

  id=$(jq -r --arg NAME "$name" '.data[]? | select(.name==$NAME) | .id' "$existing_file" | head -n1)
  payload=$(jq '{name, nodes, connections, settings, active}' "$wf")
  response_file="$TMP_DIR/upsert_$(basename "$wf" .json).json"

  operation="create"
  if [[ -n "$id" && "$id" != "null" ]]; then
    operation="update"
    echo "Update: $name ($wf, id=$id)"
    code=$(api_call "PUT" "$N8N_API_URL/workflows/$id" "$response_file" -d "$payload")
  else
    echo "Create: $name ($wf)"
    code=$(api_call "POST" "$N8N_API_URL/workflows" "$response_file" -d "$payload")
    if [[ "$code" =~ ^2 ]]; then
      id=$(jq -r '.id // empty' "$response_file")
      created=$((created + 1))
    fi
  fi

  if [[ "$code" =~ ^2 ]]; then
    if [[ "$operation" == "update" ]]; then
      updated=$((updated + 1))
    fi
    echo "OK: $name (HTTP $code)"
  else
    echo "FAIL: $name (HTTP $code)"
    cat "$response_file" || true
    failures=$((failures + 1))
    echo "---"
    continue
  fi

  if [[ "$ACTIVATE_ON_DEPLOY" == "true" && -n "${id:-}" ]]; then
    if [[ "$name" =~ $ACTIVE_EXCLUDE_REGEX ]]; then
      echo "SKIP Activate: $name (matches ACTIVE_EXCLUDE_REGEX)"
      skipped_activate=$((skipped_activate + 1))
    else
      activate_resp="$TMP_DIR/activate_${id}.json"
      act_code=$(api_call "POST" "$N8N_API_URL/workflows/$id/activate" "$activate_resp")
      if [[ "$act_code" =~ ^2 ]]; then
        echo "OK: Aktiviert $name (id=$id)"
        activated=$((activated + 1))
      else
        echo "WARN: Aktivierung fehlgeschlagen für $name (HTTP $act_code)"
        cat "$activate_resp" || true
        failures=$((failures + 1))
      fi
    fi
  fi

  echo "---"
done

echo "Summary: total=${#WORKFLOWS[@]} created=$created updated=$updated activated=$activated skipped_activate=$skipped_activate failures=$failures"

if (( failures > 0 )); then
  echo "Deploy beendet mit $failures Problem(en)."
  exit 6
fi

echo "Fertig: Alle Workflows erfolgreich deployt."
