#!/usr/bin/env python3
"""Prüft alle n8n-Workflow-JSONs im Repo-Root auf die Fehler, die EMMA früher lahmgelegt haben.

- Verbindungen müssen auf existierende Node-NAMEN zeigen (nicht auf IDs)
- keine doppelten Workflow-Namen oder Webhook-Pfade (= doppelte Workflows)
- keine abgeschalteten Gemini-Modelle
- keine SQL-Queries mit direkt eingesetzten {{ }}-Werten (bricht bei Apostrophen, SQL-Injection)
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
RETIRED_MODELS = re.compile(r"gemini-(1\.0|1\.5)")

errors = []
workflow_names = {}
webhook_paths = {}

for path in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
    fname = os.path.basename(path)
    wf = json.load(open(path, encoding="utf-8"))
    names = {n["name"] for n in wf.get("nodes", [])}

    if wf.get("name") in workflow_names:
        errors.append(f"{fname}: Workflow-Name '{wf['name']}' auch in {workflow_names[wf['name']]}")
    workflow_names[wf.get("name")] = fname

    for src, kinds in wf.get("connections", {}).items():
        if src not in names:
            errors.append(f"{fname}: Verbindung von unbekanntem Node '{src}'")
        for outputs in kinds.values():
            for output in outputs:
                for c in output or []:
                    if c["node"] not in names:
                        errors.append(f"{fname}: Verbindung zu unbekanntem Node '{c['node']}'")

    for n in wf.get("nodes", []):
        params = n.get("parameters", {})
        if n["type"] == "n8n-nodes-base.webhook":
            key = (params.get("httpMethod", "GET"), params.get("path"))
            if key in webhook_paths:
                errors.append(f"{fname}: Webhook {key} auch in {webhook_paths[key]}")
            webhook_paths[key] = fname
        if RETIRED_MODELS.search(json.dumps(params)):
            errors.append(f"{fname}: Node '{n['name']}' nutzt ein abgeschaltetes Gemini-Modell")
        if "query" in params and "{{" in params["query"]:
            errors.append(f"{fname}: Node '{n['name']}' setzt Werte direkt in SQL ein – Query-Parameter ($1, $2 …) nutzen")

for e in errors:
    print("FEHLER:", e)
print(f"{len(workflow_names)} Workflows geprüft, {len(errors)} Fehler.")
sys.exit(1 if errors else 0)
