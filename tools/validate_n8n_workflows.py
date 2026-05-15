#!/usr/bin/env python3
"""Validate the exported EMMA n8n workflow bundle for import-time hazards.

Checks covered:
- every JSON file parses
- every connection source/target uses an existing node *name* (n8n export format)
- every Basic LLM Chain has a prompt and exactly at least one connected language model
- no chain node incorrectly carries model credentials directly
- webhooks are POST-capable, and response-node workflows are configured accordingly
"""
from __future__ import annotations

import glob
import json
import sys
from pathlib import Path

ERRORS: list[str] = []


def err(path: str, msg: str) -> None:
    ERRORS.append(f"{path}: {msg}")


def walk_edges(value):
    if isinstance(value, dict):
        if "node" in value:
            yield value["node"]
        for child in value.values():
            yield from walk_edges(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_edges(child)


for path in sorted(glob.glob("*.json")):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - CLI guard
        err(path, f"invalid JSON: {exc}")
        continue

    nodes = data.get("nodes", [])
    names = {node.get("name") for node in nodes}
    chains = {node.get("name") for node in nodes if node.get("type") == "@n8n/n8n-nodes-langchain.chainLlm"}
    model_targets: dict[str, int] = {chain: 0 for chain in chains}

    node_by_name = {node.get("name"): node for node in nodes}
    for src, connection in data.get("connections", {}).items():
        if src not in names:
            err(path, f"connection source is not a node name: {src!r}")
        for ctype, groups in connection.items():
            if isinstance(groups, list) and any(group == [] for group in groups):
                err(path, f"connection {src!r}.{ctype} contains an empty output branch")
        for target in walk_edges(connection):
            if target not in names:
                err(path, f"connection target is not a node name: {target!r}")
        for group in connection.get("ai_languageModel", []) or []:
            for edge in group:
                if edge.get("node") in model_targets:
                    model_targets[edge["node"]] += 1

    for node in nodes:
        if node.get("type") == "n8n-nodes-base.switch":
            expected = len(node.get("parameters", {}).get("rules", {}).get("values", []))
            actual = len(data.get("connections", {}).get(node.get("name"), {}).get("main", []))
            if actual and expected != actual:
                err(path, f"switch {node.get('name')!r} has {expected} rules but {actual} connected outputs")

    has_respond = any(node.get("type") == "n8n-nodes-base.respondToWebhook" for node in nodes)
    for node in nodes:
        node_type = node.get("type")
        params = node.get("parameters", {})
        if node_type == "@n8n/n8n-nodes-langchain.chainLlm":
            if params.get("modelName") or "credentials" in node:
                err(path, f"chain {node.get('name')!r} still contains direct model config")
            if params.get("promptType") != "define" or not params.get("text"):
                err(path, f"chain {node.get('name')!r} has no explicit prompt")
            if model_targets.get(node.get("name"), 0) < 1:
                err(path, f"chain {node.get('name')!r} has no ai_languageModel connection")
        if node_type == "@n8n/n8n-nodes-langchain.lmChatGoogleGemini":
            if params.get("modelName") != "models/gemini-2.5-flash":
                err(path, f"Gemini model is not standardized: {node.get('name')!r} -> {params.get('modelName')!r}")
        if node_type == "n8n-nodes-base.webhook":
            if params.get("method") != "POST":
                err(path, f"webhook {node.get('name')!r} is not POST")

    has_execute_trigger = any(node.get("type") == "n8n-nodes-base.executeWorkflowTrigger" for node in nodes)
    if has_execute_trigger and has_respond:
        err(path, "workflow mixes Execute Workflow Trigger with Respond to Webhook; this can fail when called internally")

if ERRORS:
    print("Validation failed:", file=sys.stderr)
    for item in ERRORS:
        print(f"- {item}", file=sys.stderr)
    sys.exit(1)

print("Validated n8n workflow bundle successfully.")
