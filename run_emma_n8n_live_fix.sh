#!/usr/bin/env bash
set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-}"
N8N_API_KEY="${N8N_API_KEY:-}"
STRICT_API="${STRICT_API:-true}"
ACTIVATE_ON_DEPLOY="${ACTIVATE_ON_DEPLOY:-true}"
AUTO_REPAIR_BRIEFING="${AUTO_REPAIR_BRIEFING:-false}"
TARGET_TZ="${TARGET_TZ:-Europe/Berlin}"
TARGET_HOUR="${TARGET_HOUR:-8}"
TARGET_MINUTE="${TARGET_MINUTE:-0}"

if [[ -z "$N8N_BASE_URL" ]]; then
  echo "ERROR: N8N_BASE_URL fehlt."
  exit 1
fi

if [[ -z "$N8N_API_KEY" ]]; then
  echo "ERROR: N8N_API_KEY fehlt."
  exit 2
fi

log_file="emma_n8n_live_fix_$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$log_file") 2>&1

echo "== EMMA n8n live fix started =="
echo "UTC: $(date -u +'%Y-%m-%d %H:%M:%S')"
echo "N8N_BASE_URL=$N8N_BASE_URL"

echo "== Step 1/5: Validate local + remote =="
STRICT_API="$STRICT_API" N8N_BASE_URL="$N8N_BASE_URL" N8N_API_KEY="$N8N_API_KEY" ./validate_all_n8n_workflows.sh

echo "== Step 2/5: Deploy all workflows =="
ACTIVATE_ON_DEPLOY="$ACTIVATE_ON_DEPLOY" N8N_BASE_URL="$N8N_BASE_URL" N8N_API_KEY="$N8N_API_KEY" ./deploy_emma_n8n.sh

echo "== Step 3/5: Diagnose runtime =="
N8N_BASE_URL="$N8N_BASE_URL" N8N_API_KEY="$N8N_API_KEY" ./diagnose_emma_n8n.sh

echo "== Step 4/5: Repair MORNING BRIEFING schedule (dry-run) =="
DRY_RUN=true TARGET_TZ="$TARGET_TZ" TARGET_HOUR="$TARGET_HOUR" TARGET_MINUTE="$TARGET_MINUTE" \
  N8N_BASE_URL="$N8N_BASE_URL" N8N_API_KEY="$N8N_API_KEY" ./repair_emma_briefing_schedule.sh

if [[ "$AUTO_REPAIR_BRIEFING" == "true" ]]; then
  echo "== Step 5/5: Apply MORNING BRIEFING schedule patch =="
  DRY_RUN=false TARGET_TZ="$TARGET_TZ" TARGET_HOUR="$TARGET_HOUR" TARGET_MINUTE="$TARGET_MINUTE" \
    N8N_BASE_URL="$N8N_BASE_URL" N8N_API_KEY="$N8N_API_KEY" ./repair_emma_briefing_schedule.sh
else
  echo "== Step 5/5: Skip apply patch (AUTO_REPAIR_BRIEFING=false) =="
fi

echo "== EMMA n8n live fix finished =="
echo "Log: $log_file"
