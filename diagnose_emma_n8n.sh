#!/usr/bin/env bash
set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
N8N_API_URL="${N8N_API_URL:-$N8N_BASE_URL/api/v1}"
N8N_API_KEY="${N8N_API_KEY:-}"
MAX_FAILED="${MAX_FAILED:-20}"

if [[ -z "$N8N_API_KEY" ]]; then
  echo "ERROR: N8N_API_KEY fehlt."
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

call() {
  local url="$1"
  local out="$2"
  curl -sS -m 20 -o "$out" -w '%{http_code}' -H "X-N8N-API-KEY: $N8N_API_KEY" "$url" || true
}

echo "== EMMA n8n Diagnose =="
date -u +"UTC: %Y-%m-%d %H:%M:%S"
echo "Base URL: $N8N_BASE_URL"

hc=$(curl -sS -m 8 -o "$tmp/health.json" -w '%{http_code}' "$N8N_BASE_URL/rest/health" || true)
echo "health: /rest/health -> $hc"

wc=$(call "$N8N_API_URL/workflows?limit=250" "$tmp/workflows.json")
if [[ ! "$wc" =~ ^2 ]]; then
  echo "ERROR: workflows API fehlgeschlagen ($wc)"
  cat "$tmp/workflows.json" || true
  exit 2
fi

active=$(jq '[.data[] | select(.active==true)] | length' "$tmp/workflows.json")
inactive=$(jq '[.data[] | select(.active!=true)] | length' "$tmp/workflows.json")
total=$(jq '.data|length' "$tmp/workflows.json")

printf "Workflows: total=%s active=%s inactive=%s\n" "$total" "$active" "$inactive"

echo "\nTop inaktive Workflows:"
jq -r '.data[] | select(.active!=true) | "- \(.name) (id=\(.id))"' "$tmp/workflows.json" | head -n 15

fc=$(call "$N8N_API_URL/executions?status=error&limit=$MAX_FAILED" "$tmp/failed.json")
if [[ "$fc" =~ ^2 ]]; then
  failed_count=$(jq '.data|length' "$tmp/failed.json")
  echo "\nFehlgeschlagene Runs (letzte $MAX_FAILED): $failed_count"
  jq -r '.data[]? | "- exec=\(.id) workflow=\(.workflowName // .workflowId) started=\(.startedAt // "?") stopped=\(.stoppedAt // "?")"' "$tmp/failed.json" | head -n 20
else
  echo "\nWARN: executions API nicht lesbar (HTTP $fc)"
  cat "$tmp/failed.json" || true
fi

echo "\nWebhook-Testempfehlung:" 
echo "curl -X POST '$N8N_BASE_URL/webhook/emma-n8n-api-bridge' -H 'Content-Type: application/json' -d '{\"action\":\"workflow_stats\"}'"
