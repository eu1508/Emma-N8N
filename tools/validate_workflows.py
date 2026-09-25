#!/usr/bin/env python3
"""Prüft alle n8n-Workflow-JSONs im Repo-Root auf bekannte Fehler- und Sicherheitsmuster.

- Verbindungen müssen auf existierende Node-NAMEN zeigen (nicht auf IDs)
- keine doppelten Workflow-Namen oder Webhook-Pfade (= doppelte Workflows)
- jeder Webhook braucht Authentifizierung (authentication != none)
- keine Telegram-Trigger (einziger Telegram-Empfänger ist core-os)
- keine abgeschalteten Gemini-Modelle
- keine SQL-Queries mit direkt eingesetzten {{ }}-Werten (SQL-Injection)
- kein zweites Gedächtnis: keine Zugriffe auf Tabellen, die core-os gehören
- öffentliches Repo: keine privaten IP-Adressen und keine Telegram-Chat-IDs
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
RETIRED_MODELS = re.compile(r"gemini-(1\.0|1\.5)")
CORE_OS_TABLES = re.compile(r"\b(emma_memory|emma_tasks|emma_approvals|emma_agenda|interaction_memory)\b")
PRIVATE_IP = re.compile(r"\b(10\.\d{1,3}|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])|172\.(1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b")
CHAT_ID = re.compile(r"\"chatId\"\s*:\s*\"-?\d{6,}\"")

errors = []
workflow_names = {}
webhook_paths = {}

for path in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
    fname = os.path.basename(path)
    raw = open(path, encoding="utf-8").read()
    wf = json.loads(raw)
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

    if PRIVATE_IP.search(raw):
        errors.append(f"{fname}: enthält eine private/interne IP-Adresse")
    if CHAT_ID.search(raw):
        errors.append(f"{fname}: enthält eine fest eingetragene Telegram-Chat-ID")

    for n in wf.get("nodes", []):
        params = n.get("parameters", {})
        if n["type"] == "n8n-nodes-base.webhook":
            key = (params.get("httpMethod", "GET"), params.get("path"))
            if key in webhook_paths:
                errors.append(f"{fname}: Webhook {key} auch in {webhook_paths[key]}")
            webhook_paths[key] = fname
            if params.get("authentication", "none") == "none":
                errors.append(f"{fname}: Webhook '{n['name']}' ohne Authentifizierung")
        if n["type"] == "n8n-nodes-base.telegramTrigger":
            errors.append(f"{fname}: Telegram-Trigger '{n['name']}' – einziger Telegram-Empfänger ist core-os")
        if RETIRED_MODELS.search(json.dumps(params)):
            errors.append(f"{fname}: Node '{n['name']}' nutzt ein abgeschaltetes Gemini-Modell")
        query = params.get("query", "")
        if "{{" in query:
            errors.append(f"{fname}: Node '{n['name']}' setzt Werte direkt in SQL ein – Query-Parameter ($1, $2 …) nutzen")
        if CORE_OS_TABLES.search(query):
            errors.append(f"{fname}: Node '{n['name']}' nutzt eine core-os-Tabelle – Gedächtnis/Aufgaben/Freigaben nur über die core-os-API")

for e in errors:
    print("FEHLER:", e)
print(f"{len(workflow_names)} Workflows geprüft, {len(errors)} Fehler.")
sys.exit(1 if errors else 0)
