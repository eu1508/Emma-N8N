#!/usr/bin/env bash
set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
N8N_API_URL="${N8N_API_URL:-$N8N_BASE_URL/api/v1}"
N8N_API_KEY="${N8N_API_KEY:-}"
TARGET_TZ="${TARGET_TZ:-Europe/Berlin}"
TARGET_HOUR="${TARGET_HOUR:-8}"
TARGET_MINUTE="${TARGET_MINUTE:-0}"
DRY_RUN="${DRY_RUN:-true}"
NAME_MATCH="${NAME_MATCH:-MORNING BRIEFING|BRIEFING|MORNING}"

if [[ -z "$N8N_API_KEY" ]]; then
  echo "ERROR: N8N_API_KEY fehlt."
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

api_get() {
  local url="$1"
  local out="$2"
  curl -sS -m 20 -o "$out" -w '%{http_code}' -H "X-N8N-API-KEY: $N8N_API_KEY" "$url" || true
}

api_put() {
  local url="$1"
  local body="$2"
  local out="$3"
  curl -sS -m 25 -o "$out" -w '%{http_code}' \
    -X PUT "$url" \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -d "$body" || true
}

echo "== Lade Workflows =="
code=$(api_get "$N8N_API_URL/workflows?limit=250" "$tmp/workflows.json")
if [[ ! "$code" =~ ^2 ]]; then
  echo "ERROR: workflows laden fehlgeschlagen (HTTP $code)"
  cat "$tmp/workflows.json" || true
  exit 2
fi

mapfile -t candidates < <(jq -r --arg re "$NAME_MATCH" '.data[] | select(.name|test($re;"i")) | .id + "\t" + .name' "$tmp/workflows.json")

if (( ${#candidates[@]} == 0 )); then
  echo "Keine passenden Briefing-Workflows gefunden."
  exit 0
fi

echo "Gefundene Kandidaten: ${#candidates[@]}"

patched=0
for row in "${candidates[@]}"; do
  id="${row%%$'\t'*}"
  name="${row#*$'\t'}"
  detail="$tmp/wf_${id}.json"

  dcode=$(api_get "$N8N_API_URL/workflows/$id" "$detail")
  if [[ ! "$dcode" =~ ^2 ]]; then
    echo "WARN: Details nicht lesbar: $name ($id), HTTP $dcode"
    continue
  fi

  schedule_count=$(jq '[.nodes[] | select((.type=="n8n-nodes-base.scheduleTrigger") or (.type=="n8n-nodes-base.cron"))] | length' "$detail")
  if [[ "$schedule_count" == "0" ]]; then
    echo "SKIP: $name ($id) hat keine Schedule/Cron Node"
    continue
  fi

  patched_json=$(jq \
    --arg tz "$TARGET_TZ" \
    --arg h "$TARGET_HOUR" \
    --arg m "$TARGET_MINUTE" \
    '
    .nodes |= map(
      if .type=="n8n-nodes-base.scheduleTrigger" then
        .parameters = ((.parameters // {}) + {
          "rule": {"interval": [{"field":"cronExpression","expression": (($m|tonumber|tostring) + " " + ($h|tonumber|tostring) + " * * *")}]},
          "timezone": $tz
        })
      elif .type=="n8n-nodes-base.cron" then
        .parameters = ((.parameters // {}) + {
          "triggerTimes": {"item": [{"mode":"everyDay","hour": ($h|tonumber), "minute": ($m|tonumber)}]},
          "timezone": $tz
        })
      else . end
    )
    | {name, nodes, connections, settings, active}
    ' "$detail")

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN: würde patchen -> $name ($id), schedule_nodes=$schedule_count, time=${TARGET_HOUR}:${TARGET_MINUTE} tz=$TARGET_TZ"
    patched=$((patched + 1))
    continue
  fi

  out="$tmp/put_${id}.json"
  pcode=$(api_put "$N8N_API_URL/workflows/$id" "$patched_json" "$out")
  if [[ "$pcode" =~ ^2 ]]; then
    echo "OK: gepatcht -> $name ($id)"
    patched=$((patched + 1))
  else
    echo "FAIL: patch fehlgeschlagen -> $name ($id), HTTP $pcode"
    cat "$out" || true
  fi
done

echo "Fertig. Bearbeitet: $patched (DRY_RUN=$DRY_RUN)"
