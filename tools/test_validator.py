#!/usr/bin/env python3
"""Beweist, dass validate_workflows.py wirklich fehlschlägt: baut aus den echten Workflows je EINEN Fehler nach
und erwartet, dass der Validator genau daran scheitert. Aufruf: python3 tools/test_validator.py"""
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def node(wf, name):
    return next(n for n in wf["nodes"] if n["name"] == name)


def code_of(wf, name):
    return node(wf, name)["parameters"]["jsCode"]


MUTATIONS = {
    "Webhook ohne Authentifizierung": ("EMMA_ENGINE_HUB", "ohne Header-Authentifizierung",
                                       lambda wf: node(wf, "Engine Webhook")["parameters"].__setitem__("authentication", "none")),
    "Webhook ohne Credential": ("EMMA_ENGINE_HUB", "kein Credential zugeordnet",
                                lambda wf: node(wf, "Engine Webhook").pop("credentials")),
    "Telegram-Node": ("EMMA_ENGINE_HUB", "spricht Telegram",
                      lambda wf: wf["nodes"].append({"name": "TG", "type": "n8n-nodes-base.telegram", "parameters": {}, "position": [0, 0]})),
    "Telegram per HTTP": ("EMMA_PROPOSE", "spricht Telegram",
                          lambda wf: wf["nodes"].append({"name": "TG", "type": "n8n-nodes-base.httpRequest", "parameters": {"url": "https://api.telegram.org/bot/sendMessage"}, "position": [0, 0]})),
    "JARVIS": ("EMMA_WAKE_TIMER", "JARVIS", lambda wf: wf["nodes"].append({"name": "ask_jarvis", "type": "n8n-nodes-base.noOp", "parameters": {}, "position": [0, 0]})),
    "KI-Aufruf ohne Budget-Check": ("EMMA_ENGINE_HUB", "ohne vorgeschalteten Budget-Check",
                                    lambda wf: node(wf, "Budget prüfen")["parameters"].__setitem__("query", "SELECT 1;")),
    "KI-Aufruf ohne Nutzungslog": ("EMMA_MASTER_ORCHESTRATOR", "ohne nachgeschaltetes Logging",
                                   lambda wf: node(wf, "Verbrauch loggen")["parameters"].__setitem__("query", "SELECT 1;")),
    "onError=continue ohne Log": ("EMMA_COGNITIVE_LOOP", "danach wird nichts protokolliert",
                                  lambda wf: wf["nodes"].append({"name": "Stumm", "type": "n8n-nodes-base.noOp", "parameters": {}, "position": [0, 0], "onError": "continueRegularOutput"})),
    "interne IP": ("EMMA_PROPOSE", "private/interne IP",
                   lambda wf: node(wf, "Konfiguration")["parameters"].__setitem__("jsCode", "const u = 'http://" + ".".join(["10", "1", "2", "3"]) + ":2047';")),
    "Chat-ID": ("EMMA_PROPOSE", "Telegram-Chat-ID",
                lambda wf: node(wf, "Konfiguration")["parameters"].__setitem__("jsCode", 'const cfg = { "chat' + 'Id": "' + "1" * 9 + '" };')),
    "feste Drive-ID": ("EMMA_APPROVED_EXECUTOR", "Google-ID",
                       lambda wf: node(wf, "Notiz schreiben")["parameters"]["folderId"].__setitem__("value", "1" + "a" * 32)),
    "Allowlist erlaubt Code": ("EMMA_APPROVED_EXECUTOR", "Allowlist",
                               lambda wf: node(wf, "Workflow prüfen")["parameters"].__setitem__("jsCode", code_of(wf, "Workflow prüfen").replace('new Set(["', 'new Set(["n8n-nodes-base.code", "', 1))),
    "Allowlist weicht ab": ("EMMA_SELF_BUILDER", "weicht von den anderen ab",
                            lambda wf: node(wf, "Parse Workflow")["parameters"].__setitem__("jsCode", code_of(wf, "Parse Workflow").replace('new Set(["', 'new Set(["n8n-nodes-base.wait", "', 1))),
    "Zeitplan ohne Zeitzone": ("EMMA_COGNITIVE_LOOP", "settings.timezone",
                               lambda wf: wf["settings"].pop("timezone")),
    "core-os-Tabelle im Workflow": ("EMMA_ENGINE_HUB", "core-os-Tabelle",
                                    lambda wf: node(wf, "Budget prüfen")["parameters"].__setitem__("query", "SELECT emma_budget_spent() FROM emma_memory;")),
}


def run(directory):
    p = subprocess.run([sys.executable, os.path.join(directory, "tools", "validate_workflows.py")], capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout


def main():
    code, out = run(ROOT)
    if code != 0:
        print("Ausgangslage ist nicht sauber:\n" + out)
        return 1
    failed = 0
    for label, (workflow, expected, mutate) in MUTATIONS.items():
        with tempfile.TemporaryDirectory() as tmp:
            shutil.copytree(ROOT, tmp, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git"))
            path = os.path.join(tmp, workflow + ".json")
            wf = json.load(open(path, encoding="utf-8"))
            mutate(wf)
            json.dump(wf, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
            code, out = run(tmp)
        ok = code != 0 and expected in out
        failed += not ok
        print(("OK      " if ok else "FEHLER  ") + f"{label}: Validator {'scheitert wie erwartet' if ok else 'hat den Fehler NICHT erkannt'}")
    print(f"\n{len(MUTATIONS) - failed} von {len(MUTATIONS)} Fehlerfällen erkannt.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
