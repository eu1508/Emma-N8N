#!/usr/bin/env python3
"""Prüft, ob core-os die Endpunkte anbietet, die die n8n-Workflows aufrufen. Nur lesend: es werden ausschließlich
GET-Anfragen geschickt, nichts wird angelegt oder geändert.

Aufruf (auf dem NAS oder einem Rechner, der core-os erreicht):
    CORE_OS_URL=http://<core-os>:<port> python3 tools/check_core_os.py

Optional, falls core-os ein Token verlangt (wie im n8n-Credential „core-os API“):
    CORE_OS_AUTH_HEADER=Authorization CORE_OS_TOKEN='Bearer …'

Bei Routen, die nur POST/PATCH annehmen, heißt die Antwort 405 auf GET „Route vorhanden“, 404 heißt „fehlt“.
Antwortet ein Pfad auf GET mit 200 (z. B. /api/v1/tasks als Liste), ist offen, ob auch POST geht: das Skript
meldet ❔, weil es nichts anlegt. Exit-Code 0 nur, wenn alles bestätigt ist."""
import json
import os
import sys
import urllib.error
import urllib.request

PROBE_ID = "n8n-probe-0"

# (Pfad, Methode in n8n, Prüfung) – Prüfung "json:context" / "json:approvals" liest die Antwort, "route" nur die Route.
CHECKS = [
    ("/api/v1/context?for=n8n", "GET", "json:context", "Kontext für Loop und Orchestrator"),
    ("/api/v1/approvals?source=n8n&status=approved", "GET", "json:approvals", "freigegebene Vorschläge (Executor)"),
    ("/api/v1/approvals", "POST", "route", "Freigabe anfragen (EMMA_PROPOSE)"),
    (f"/api/v1/approvals/{PROBE_ID}/result", "POST", "route", "Ergebnis melden (Executor)"),
    ("/api/v1/memory/facts", "POST", "route", "Merken (Loop, Orchestrator)"),
    ("/api/v1/tasks", "POST", "route", "Aufgabe anlegen (Loop)"),
    (f"/api/v1/tasks/{PROBE_ID}", "PATCH", "route", "Aufgabe erledigen (Loop)"),
]


def get(base, path, headers, timeout=10):
    req = urllib.request.Request(base.rstrip("/") + path, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def judge_json(kind, body):
    try:
        data = json.loads(body or b"null")
    except ValueError:
        return False, "Antwort ist kein JSON"
    if kind == "context":
        if not isinstance(data, dict):
            return False, "kein Objekt"
        missing = [k for k in ("memory", "recent_chat", "tasks", "agenda") if not isinstance(data.get(k), list)]
        return (not missing), ("ok" if not missing else "Listen fehlen: " + ", ".join(missing))
    items = data if isinstance(data, list) else next(
        (data.get(k) for k in ("approvals", "items", "data") if isinstance(data, dict) and isinstance(data.get(k), list)), None)
    return items is not None, ("ok" if items is not None else "keine Liste (approvals/items/data)")


def run(base, headers, out=print):
    results = []
    for path, method, check, purpose in CHECKS:
        try:
            status, body = get(base, path, headers)
        except (urllib.error.URLError, OSError) as e:
            results.append((False, method, path, purpose, f"nicht erreichbar ({getattr(e, 'reason', e)})"))
            continue
        if status in (401, 403):
            ok, note = False, f"{status}: Token/Header prüfen"
        elif check.startswith("json:"):
            ok, note = (judge_json(check[5:], body) if 200 <= status < 300 else (False, f"HTTP {status}"))
        elif status == 404:
            ok, note = False, "404: Route fehlt" + (" (oder nur die Test-ID unbekannt)" if PROBE_ID in path else "")
        elif status == 405:
            ok, note = True, "Route vorhanden (GET → 405)"
        elif 200 <= status < 300:
            ok, note = None, f"Pfad antwortet auf GET ({status}), ob {method} geht, lässt sich nur schreibend prüfen"
        else:
            ok, note = False, f"unklar (HTTP {status})"
        results.append((ok, method, path, purpose, note))
    for ok, method, path, purpose, note in results:
        out(f"{'✅' if ok else '❔' if ok is None else '❌'} {method:5} {path:48} {purpose}: {note}")
    good = sum(r[0] is True for r in results)
    unclear = sum(r[0] is None for r in results)
    out(f"{good} von {len(results)} Endpunkten bestätigt" + (f", {unclear} unklar (❔)." if unclear else "."))
    return good == len(results)


def main():
    base = os.environ.get("CORE_OS_URL") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not base:
        print("CORE_OS_URL setzen (Basis-URL von core-os).", file=sys.stderr)
        return 2
    headers = {"Accept": "application/json"}
    token = os.environ.get("CORE_OS_TOKEN")
    if token:
        headers[os.environ.get("CORE_OS_AUTH_HEADER", "Authorization")] = token
    return 0 if run(base, headers) else 1


if __name__ == "__main__":
    sys.exit(main())
