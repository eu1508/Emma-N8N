#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

show_help() {
  cat <<'EOF'
EMMA n8n Installer

Usage:
  ./install_in_n8n.sh check      # local checks only
  ./install_in_n8n.sh deploy     # create/update workflows in n8n
  ./install_in_n8n.sh activate   # create/update and activate workflows

Before deploy/activate:
  1) Rotate any API keys that were shared in chat/logs.
  2) Copy .env.n8n.example to .env.n8n.
  3) Put your real N8N_BASE_URL and N8N_API_KEY into .env.n8n.
EOF
}

ensure_env_file() {
  if [[ ! -f .env.n8n ]]; then
    cp .env.n8n.example .env.n8n
    cat <<'EOF'
Created .env.n8n from .env.n8n.example.
Open .env.n8n now and replace n8n_api_REPLACE_ME with a NEW real n8n API key.
Do not reuse keys that were posted in chat/logs.
EOF
    exit 2
  fi
}

run_checks() {
  python3 tools/scan_secrets.py
  python3 tools/validate_n8n_workflows.py
  python3 tools/deploy_n8n_bundle.py
}

command="${1:-help}"
case "$command" in
  check)
    run_checks
    ;;
  deploy)
    ensure_env_file
    python3 tools/scan_secrets.py
    python3 tools/validate_n8n_workflows.py
    python3 tools/deploy_n8n_bundle.py --apply
    ;;
  activate)
    ensure_env_file
    python3 tools/scan_secrets.py
    python3 tools/validate_n8n_workflows.py
    python3 tools/deploy_n8n_bundle.py --apply --activate
    ;;
  help|-h|--help)
    show_help
    ;;
  *)
    show_help >&2
    exit 2
    ;;
esac
