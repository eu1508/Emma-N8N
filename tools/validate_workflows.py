#!/usr/bin/env python3
"""Prüft alle n8n-Workflow-JSONs im Repo-Root auf bekannte Fehler- und Sicherheitsmuster.

Aufbau und Verbindungen
- Verbindungen müssen auf existierende Node-NAMEN zeigen (nicht auf IDs)
- keine doppelten Workflow-Namen oder Webhook-Pfade (= doppelte Workflows)
- Workflows mit Zeitplan oder Wait-Node setzen ihre Zeitzone selbst (die n8n-Instanz hat eine andere)

Sicherheit
- jeder Webhook braucht Header-Auth MIT zugeordnetem Credential (authentication=none oder fehlend = Fehler)
- kein Telegram in n8n: weder Telegram-Nodes noch Aufrufe von api.telegram.org (einziger Empfänger und Sender ist core-os)
- kein JARVIS in n8n (Quarantäne)
- keine SQL-Queries mit direkt eingesetzten {{ }}-Werten (SQL-Injection)
- kein zweites Gedächtnis: keine Zugriffe auf und keine CREATE TABLE für Tabellen, die core-os gehören
- Selbst-Builder und Executor prüfen mit derselben Allowlist, und die enthält weder Code, Execute Command,
  HTTP-Requests, Webhooks noch Telegram/E-Mail

Kosten und Fehlerbehandlung
- vor JEDEM KI-Aufruf steht ein Budget-Check (emma_budget_spent), zwischen zwei aufeinanderfolgenden Aufrufen ebenfalls
- nach jedem KI-Aufruf folgt ein Eintrag in llm_usage
- kein onError=continue ohne Protokoll: dahinter muss ein Postgres-Knoten in ein Log schreiben
- abgeschaltete Gemini-Modelle

Öffentliches Repo (alle Textdateien)
- keine privaten/internen IP-Adressen, keine Telegram-Chat-IDs, keine Token- oder Schlüsselmuster
- keine fest eingetragenen Google-Drive-Ordner- oder Kalender-IDs (kommen aus Umgebungsvariablen)
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RETIRED_MODELS = re.compile(r"gemini-(1\.0|1\.5)")
CORE_OS_TABLES = ("emma_memory", "emma_tasks", "emma_approvals", "emma_agenda", "interaction_memory")
CORE_OS_TABLES_RE = re.compile(r"\b(" + "|".join(CORE_OS_TABLES) + r")\b")
CREATE_CORE_OS_TABLE = re.compile(r"CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(" + "|".join(CORE_OS_TABLES) + r")\b", re.I)
PRIVATE_IP = re.compile(r"\b(10\.\d{1,3}|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])|172\.(1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b")
CHAT_ID = re.compile(r"chat[_ ]?id\W{0,8}-?\d{6,}", re.I)  # auch in JSON-Strings mit maskierten Anführungszeichen
SECRET_PATTERNS = {
    "Telegram-Bot-Token": re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{30,}\b"),
    "OpenAI-/Anthropic-Schlüssel": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "Google-API-Schlüssel": re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    "JWT": re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
    "privater Schlüssel": re.compile(r"-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----"),
}
DRIVE_ID_IN_CODE = re.compile(r"['\"]1[A-Za-z0-9_-]{32}['\"]")
CALENDAR_ID = re.compile(r"c_[0-9a-f]{20,}@group\.calendar\.google\.com")
LLM_TYPES = ("@n8n/n8n-nodes-langchain.chainLlm", "@n8n/n8n-nodes-langchain.agent", "@n8n/n8n-nodes-langchain.chainSummarization")
LOG_TABLES = ("emma_action_log", "emma_events", "emma_cycles", "n8n_action_queue", "workflow_registry")
FORBIDDEN_IN_ALLOWLIST = re.compile(r"code|executecommand|httprequest|webhook|ssh|ftp|email|telegram", re.I)

errors = []
workflow_names = {}
webhook_paths = {}
allowlists = {}


def query_of(node):
    return str(node.get("parameters", {}).get("query", ""))


def reach_map(wf):
    """Node -> alle Nodes, die über main-Verbindungen danach erreichbar sind."""
    succ = {}
    for src, kinds in wf.get("connections", {}).items():
        for outputs in kinds.get("main", []):
            for c in outputs or []:
                succ.setdefault(src, set()).add(c["node"])
    reach = {}
    for start in {n["name"] for n in wf.get("nodes", [])}:
        seen, stack = set(), [start]
        while stack:
            for nxt in succ.get(stack.pop(), ()):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        reach[start] = seen
    return reach


for path in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
    fname = os.path.basename(path)
    raw = open(path, encoding="utf-8").read()
    wf = json.loads(raw)
    nodes = wf.get("nodes", [])
    names = {n["name"] for n in nodes}
    by_name = {n["name"]: n for n in nodes}

    if re.search(r"memory", fname, re.I) and "nodes" not in wf:
        errors.append(f"{fname}: Gedächtnis-Exportdatei – kein zweites Gedächtnis, core-os ist die einzige Wahrheit")

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

    if re.search(r"jarvis", raw, re.I):
        errors.append(f"{fname}: enthält JARVIS – bleibt in Quarantäne, bis der Nutzer entscheidet")

    reach = reach_map(wf)
    if any(n["type"] in ("n8n-nodes-base.scheduleTrigger", "n8n-nodes-base.wait") for n in nodes) and wf.get("settings", {}).get("timezone") != "Europe/Berlin":
        errors.append(f"{fname}: Zeitplan/Wait ohne settings.timezone=Europe/Berlin (die n8n-Instanz läuft in einer anderen Zeitzone)")

    budget_nodes = {n["name"] for n in nodes if n["type"] == "n8n-nodes-base.postgres" and "emma_budget_spent" in query_of(n)}
    usage_nodes = {n["name"] for n in nodes if n["type"] == "n8n-nodes-base.postgres" and "llm_usage" in query_of(n)}
    log_nodes = {n["name"] for n in nodes if n["type"] == "n8n-nodes-base.postgres" and any(t in query_of(n) for t in LOG_TABLES)}
    llm_nodes = [n["name"] for n in nodes if n["type"] in LLM_TYPES]
    for llm in llm_nodes:
        if not any(llm in reach[b] for b in budget_nodes):
            errors.append(f"{fname}: KI-Node '{llm}' ohne vorgeschalteten Budget-Check (emma_budget_spent)")
        if not (reach[llm] & usage_nodes):
            errors.append(f"{fname}: KI-Node '{llm}' ohne nachgeschaltetes Logging in llm_usage")
        for other in llm_nodes:
            if other != llm and llm in reach[other] and not any(b in reach[other] and llm in reach[b] for b in budget_nodes):
                errors.append(f"{fname}: zwischen den KI-Nodes '{other}' und '{llm}' fehlt ein erneuter Budget-Check")

    if PRIVATE_IP.search(raw):
        errors.append(f"{fname}: enthält eine private/interne IP-Adresse")
    if CHAT_ID.search(raw):
        errors.append(f"{fname}: enthält eine fest eingetragene Telegram-Chat-ID")
    if CALENDAR_ID.search(raw) or DRIVE_ID_IN_CODE.search(raw):
        errors.append(f"{fname}: enthält eine fest eingetragene Google-Kalender- oder Drive-Ordner-ID – per Umgebungsvariable setzen")

    for n in nodes:
        params = n.get("parameters", {})
        dumped = json.dumps(params)
        if n["type"] == "n8n-nodes-base.webhook":
            key = (params.get("httpMethod", "GET"), params.get("path"))
            if key in webhook_paths:
                errors.append(f"{fname}: Webhook {key} auch in {webhook_paths[key]}")
            webhook_paths[key] = fname
            if params.get("authentication", "none") != "headerAuth":
                errors.append(f"{fname}: Webhook '{n['name']}' ohne Header-Authentifizierung (authentication={params.get('authentication', 'none')})")
            elif "httpHeaderAuth" not in (n.get("credentials") or {}):
                errors.append(f"{fname}: Webhook '{n['name']}' verlangt Header-Auth, hat aber kein Credential zugeordnet")
        if "telegram" in n["type"].lower() or "api.telegram.org" in dumped:
            errors.append(f"{fname}: Node '{n['name']}' spricht Telegram – einziger Telegram-Empfänger und -Sender ist core-os")
        if RETIRED_MODELS.search(dumped):
            errors.append(f"{fname}: Node '{n['name']}' nutzt ein abgeschaltetes Gemini-Modell")
        query = params.get("query", "")
        if "{{" in query:
            errors.append(f"{fname}: Node '{n['name']}' setzt Werte direkt in SQL ein – Query-Parameter ($1, $2 …) nutzen")
        if CORE_OS_TABLES_RE.search(query):
            errors.append(f"{fname}: Node '{n['name']}' nutzt eine core-os-Tabelle – Gedächtnis/Aufgaben/Freigaben nur über die core-os-API")
        if n["type"] in ("n8n-nodes-base.googleDrive", "n8n-nodes-base.googleCalendar"):
            for value in params.values():
                if isinstance(value, dict) and value.get("__rl") and value.get("mode") == "id":
                    v = str(value.get("value", ""))
                    if v and not v.startswith("=") and v != "primary":
                        errors.append(f"{fname}: Node '{n['name']}' hat eine fest eingetragene Google-ID – per Umgebungsvariable setzen")
        if n.get("onError", "").startswith("continue") or n.get("continueOnFail"):
            if not (reach[n["name"]] & log_nodes):
                errors.append(f"{fname}: Node '{n['name']}' läuft bei Fehlern weiter (onError=continue), aber danach wird nichts protokolliert")
        code = params.get("jsCode", "")
        m = re.search(r"const ALLOWED = new Set\((\[.*?\])\)", code, re.S)
        if m and n["name"] in ("Parse Workflow", "Workflow prüfen"):
            allowlists[(fname, n["name"])] = set(json.loads(m.group(1)))

if allowlists:
    reference = next(iter(allowlists.values()))
    for (fname, node), types in allowlists.items():
        if types != reference:
            errors.append(f"{fname}: Allowlist in '{node}' weicht von den anderen ab – Selbst-Builder und Executor müssen dieselbe nutzen")
        for t in sorted(types):
            if FORBIDDEN_IN_ALLOWLIST.search(t.replace("executeWorkflowTrigger", "")):
                errors.append(f"{fname}: Allowlist in '{node}' erlaubt '{t}' (Code, Execute Command, HTTP, Webhook, E-Mail und Telegram sind verboten)")
else:
    errors.append("keine Allowlist für generierte Workflows gefunden (EMMA_SELF_BUILDER/EMMA_APPROVED_EXECUTOR)")

# Öffentliches Repo: auch Dokumentation, Schema, Skripte und CI durchsuchen (außer dieser Datei mit ihren Mustern).
this_file = os.path.abspath(__file__)
for path in sorted(glob.glob(os.path.join(ROOT, "**", "*"), recursive=True)):
    if os.path.isdir(path) or os.path.abspath(path) == this_file or "/.git/" in path.replace("\\", "/"):
        continue
    if not path.endswith((".md", ".sql", ".yml", ".yaml", ".py", ".js", ".txt")) and not path.endswith(".json"):
        continue
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    text = open(path, encoding="utf-8", errors="ignore").read()
    if not path.endswith(".json") and PRIVATE_IP.search(text):
        errors.append(f"{rel}: enthält eine private/interne IP-Adresse")
    if not path.endswith(".json") and CHAT_ID.search(text):
        errors.append(f"{rel}: enthält eine fest eingetragene Telegram-Chat-ID")
    for label, rx in SECRET_PATTERNS.items():
        if rx.search(text):
            errors.append(f"{rel}: enthält ein Muster für {label}")
    if rel.endswith(".sql") and CREATE_CORE_OS_TABLE.search(text):
        errors.append(f"{rel}: legt eine Tabelle an, die core-os gehört – kein zweites Gedächtnis")

for e in errors:
    print("FEHLER:", e)
print(f"{len(workflow_names)} Workflows geprüft, {len(errors)} Fehler.")
sys.exit(1 if errors else 0)
