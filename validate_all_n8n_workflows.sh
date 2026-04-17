#!/usr/bin/env bash
set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
N8N_API_URL="${N8N_API_URL:-$N8N_BASE_URL/api/v1}"
N8N_API_KEY="${N8N_API_KEY:-}"
JSON_GLOB_REGEX="${JSON_GLOB_REGEX:-\.json$}"
STRICT_API="${STRICT_API:-false}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapfile -t JSON_FILES < <(rg --files | rg "$JSON_GLOB_REGEX" | sort)
if (( ${#JSON_FILES[@]} == 0 )); then
  echo "ERROR: keine JSON-Dateien gefunden"
  exit 1
fi

errors=0
wf_count=0

echo "== Lokale Workflow-Validierung =="
for f in "${JSON_FILES[@]}"; do
  if ! jq -e . "$f" >/dev/null 2>&1; then
    echo "FAIL JSON parse: $f"
    errors=$((errors + 1))
    continue
  fi

  if ! jq -e 'has("name") and has("nodes") and has("connections") and (.nodes|type=="array") and (.connections|type=="object")' "$f" >/dev/null 2>&1; then
    continue
  fi

  wf_count=$((wf_count + 1))

  name=$(jq -r '.name' "$f")
  node_count=$(jq '.nodes|length' "$f")
  if (( node_count == 0 )); then
    echo "FAIL leere nodes: $f ($name)"
    errors=$((errors + 1))
  fi

  dup_ids=$(jq -r '.nodes | group_by(.id)[] | select(length>1) | .[0].id' "$f")
  if [[ -n "$dup_ids" ]]; then
    echo "FAIL doppelte node id in $f: $dup_ids"
    errors=$((errors + 1))
  fi

done

echo "Gefundene lokale Workflows: $wf_count"

if [[ -n "$N8N_API_KEY" ]]; then
  echo "== Remote n8n API-Validierung =="
  code=$(curl -sS -m 20 -o "$tmp/remote.json" -w '%{http_code}' \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_API_URL/workflows?limit=500" || true)

  if [[ "$code" =~ ^2 ]]; then
    local_names="$tmp/local_names.txt"
    remote_names="$tmp/remote_names.txt"

    jq -r 'select(has("name") and has("nodes") and has("connections")) | .name' "${JSON_FILES[@]}" | sort -u > "$local_names"
    jq -r '.data[]?.name' "$tmp/remote.json" | sort -u > "$remote_names"

    missing_remote=$(comm -23 "$local_names" "$remote_names" || true)
    if [[ -n "$missing_remote" ]]; then
      echo "WARN nicht in n8n deployed:"
      echo "$missing_remote"
      if [[ "$STRICT_API" == "true" ]]; then
        errors=$((errors + 1))
      fi
    fi

    inactive_remote=$(jq -r '.data[] | select(.active!=true) | "- " + .name + " (id=" + (.id|tostring) + ")"' "$tmp/remote.json")
    if [[ -n "$inactive_remote" ]]; then
      echo "Hinweis: inaktive Workflows in n8n:"
      echo "$inactive_remote" | head -n 30
    fi
  else
    echo "WARN n8n API nicht erreichbar/autorisiert (HTTP $code)"
    cat "$tmp/remote.json" || true
    if [[ "$STRICT_API" == "true" ]]; then
      errors=$((errors + 1))
    fi
  fi
else
  echo "== Remote n8n API-Validierung übersprungen (kein N8N_API_KEY) =="
fi

if (( errors > 0 )); then
  echo "VALIDATION FAIL: $errors Problem(e) gefunden"
  exit 2
fi

echo "VALIDATION OK"
