#!/usr/bin/env python3
"""Deploy the EMMA n8n workflow bundle to a live n8n instance.

The script intentionally defaults to dry-run. Use --apply when N8N_BASE_URL and
N8N_API_KEY are set and you want to create/update workflows through the n8n
public API.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MASTER_NAME = "METROPOLIS_MASTER_ORCHESTRATOR_V14"
ERROR_WORKFLOW_NAME = "METROPOLIS_ERROR_GUARDIAN"


def workflow_files() -> list[Path]:
    files = sorted(ROOT.glob("*.json"))
    return sorted(files, key=lambda path: (json.loads(path.read_text(encoding="utf-8")).get("name") == MASTER_NAME, path.name))


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def load_workflow(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    for key in ("id", "versionId", "triggerCount", "updatedAt", "createdAt", "shared", "tags"):
        data.pop(key, None)
    data.setdefault("settings", {}).setdefault("executionOrder", "v1")
    return data


class N8nClient:
    def __init__(self, base_url: str, api_key: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            method=method,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "X-N8N-API-KEY": self.api_key,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                raw = response.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path} failed with HTTP {exc.code}: {detail}") from exc

    def list_workflows(self) -> dict[str, dict[str, Any]]:
        workflows: dict[str, dict[str, Any]] = {}
        cursor = None
        while True:
            query = "?limit=250" + (f"&cursor={urllib.parse.quote(cursor)}" if cursor else "")
            response = self.request("GET", f"/api/v1/workflows{query}")
            data = response.get("data", response if isinstance(response, list) else [])
            for workflow in data:
                if workflow.get("name"):
                    workflows[workflow["name"]] = workflow
            cursor = response.get("nextCursor") if isinstance(response, dict) else None
            if not cursor:
                return workflows

    def create_workflow(self, workflow: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v1/workflows", workflow)

    def update_workflow(self, workflow_id: str, workflow: dict[str, Any]) -> dict[str, Any]:
        return self.request("PUT", f"/api/v1/workflows/{workflow_id}", workflow)

    def activate_workflow(self, workflow_id: str) -> None:
        self.request("POST", f"/api/v1/workflows/{workflow_id}/activate")


def patch_master_mapping(master: dict[str, Any], live_ids_by_name: dict[str, str]) -> None:
    for node in master.get("nodes", []):
        if node.get("name") != "EXECUTE_ENGINE":
            continue
        workflow_id_expr = node.get("parameters", {}).get("workflowId", "")
        if "[$json.engine]" not in workflow_id_expr:
            continue
        mapping_text = workflow_id_expr.split("={{ ", 1)[1].split("[$json.engine]", 1)[0].strip()
        mapping = json.loads(mapping_text)
        patched = {skill: live_ids_by_name.get(workflow_name, workflow_name) for skill, workflow_name in mapping.items()}
        node["parameters"]["workflowId"] = "={{ " + json.dumps(patched, ensure_ascii=False) + "[$json.engine] || " + json.dumps(live_ids_by_name.get("METROPOLIS_OPERATIONS_ENGINE", "METROPOLIS_OPERATIONS_ENGINE")) + " }}"


def set_error_workflow(workflow: dict[str, Any], live_error_id: str | None) -> None:
    if not live_error_id or workflow.get("name") == ERROR_WORKFLOW_NAME:
        return
    workflow.setdefault("settings", {})["errorWorkflow"] = live_error_id


def main() -> int:
    parser = argparse.ArgumentParser(description="Create or update EMMA workflows in n8n via the public API.")
    parser.add_argument("--apply", action="store_true", help="perform API writes; otherwise only print the plan")
    parser.add_argument("--activate", action="store_true", help="activate workflows after create/update")
    parser.add_argument("--no-error-workflow", action="store_true", help="do not set METROPOLIS_ERROR_GUARDIAN as workflow error handler")
    parser.add_argument("--env-file", default=".env.n8n", help="optional env file containing N8N_BASE_URL and N8N_API_KEY")
    args = parser.parse_args()
    load_env_file(ROOT / args.env_file)

    files = workflow_files()
    workflows = [load_workflow(path) for path in files]
    names = [workflow["name"] for workflow in workflows]
    print(f"Found {len(workflows)} workflow exports: {', '.join(names)}")

    if not args.apply:
        print("Dry-run only. Set N8N_BASE_URL, N8N_API_KEY and pass --apply to bind these workflows into n8n.")
        return 0

    base_url = os.environ.get("N8N_BASE_URL")
    api_key = os.environ.get("N8N_API_KEY")
    if not base_url or not api_key:
        print("N8N_BASE_URL and N8N_API_KEY are required with --apply.", file=sys.stderr)
        return 2
    if "REPLACE_ME" in api_key or api_key.strip() in {"n8n_api_...", ""}:
        print("N8N_API_KEY still looks like a placeholder. Put your real API key in .env.n8n before --apply.", file=sys.stderr)
        return 2

    client = N8nClient(base_url, api_key)
    existing = client.list_workflows()
    live_ids_by_name = {name: str(workflow.get("id")) for name, workflow in existing.items() if workflow.get("id")}

    # First pass: create/update every non-master workflow so the master can map to live IDs.
    for workflow in workflows:
        if workflow["name"] == MASTER_NAME:
            continue
        workflow_id = live_ids_by_name.get(workflow["name"])
        if not args.no_error_workflow:
            set_error_workflow(workflow, live_ids_by_name.get(ERROR_WORKFLOW_NAME))
        result = client.update_workflow(workflow_id, workflow) if workflow_id else client.create_workflow(workflow)
        live_ids_by_name[workflow["name"]] = str(result.get("id", workflow_id or workflow["name"]))
        print(f"Bound {workflow['name']} -> {live_ids_by_name[workflow['name']]}")
        time.sleep(0.1)

    # Second pass: patch and bind master against real instance IDs.
    for workflow in workflows:
        if workflow["name"] != MASTER_NAME:
            continue
        patch_master_mapping(workflow, live_ids_by_name)
        if not args.no_error_workflow:
            set_error_workflow(workflow, live_ids_by_name.get(ERROR_WORKFLOW_NAME))
        workflow_id = live_ids_by_name.get(workflow["name"])
        result = client.update_workflow(workflow_id, workflow) if workflow_id else client.create_workflow(workflow)
        live_ids_by_name[workflow["name"]] = str(result.get("id", workflow_id or workflow["name"]))
        print(f"Bound {workflow['name']} -> {live_ids_by_name[workflow['name']]}")

    if args.activate:
        for name, workflow_id in live_ids_by_name.items():
            if name in names:
                client.activate_workflow(workflow_id)
                print(f"Activated {name}")
                time.sleep(0.1)

    print("n8n binding complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
