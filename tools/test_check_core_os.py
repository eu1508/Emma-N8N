#!/usr/bin/env python3
"""Testet check_core_os.py gegen einen kleinen Schein-core-os auf localhost. Aufruf: python3 tools/test_check_core_os.py"""
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_core_os  # noqa: E402

SEEN = []


def make_handler(routes):
    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            SEEN.append(self.command)
            status, body = routes.get(self.path, (404, {"detail": "Not Found"}))
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *a):
            pass
    return H


def serve(routes):
    srv = HTTPServer(("127.0.0.1", 0), make_handler(routes))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_port}"


FULL = {
    "/api/v1/context?for=n8n": (200, {"memory": [], "recent_chat": [], "tasks": [], "agenda": []}),
    "/api/v1/approvals?source=n8n&status=approved": (200, {"approvals": []}),
    "/api/v1/approvals": (405, {}),
    f"/api/v1/approvals/{check_core_os.PROBE_ID}/result": (405, {}),
    "/api/v1/memory/facts": (405, {}),
    "/api/v1/tasks": (405, {}),
    f"/api/v1/tasks/{check_core_os.PROBE_ID}": (405, {}),
}

failures = 0


def case(name, routes, expect_ok, must_contain=None):
    global failures
    srv, base = serve(routes)
    lines = []
    ok = check_core_os.run(base, {}, out=lines.append)
    srv.shutdown()
    text = "\n".join(lines)
    good = ok == expect_ok and (must_contain is None or must_contain in text)
    failures += not good
    print(f"{'ok ' if good else 'FEHLER'} {name}" + ("" if good else "\n" + text))


case("alles vorhanden", FULL, True)
case("Freigabe-Ergebnis fehlt", {k: v for k, v in FULL.items() if not k.endswith("/result")}, False, "Route fehlt")
case("Kontext unvollständig", {**FULL, "/api/v1/context?for=n8n": (200, {"memory": []})}, False, "Listen fehlen")
case("Token fehlt", {**FULL, "/api/v1/tasks": (401, {})}, False, "Token")
case("Freigaben keine Liste", {**FULL, "/api/v1/approvals?source=n8n&status=approved": (200, {"x": 1})}, False, "keine Liste")
case("POST-Route nur per GET sichtbar", {**FULL, "/api/v1/approvals": (200, {"approvals": []})}, False, "❔")
if set(SEEN) != {"GET"}:
    failures += 1
    print("FEHLER: Prüfskript hat nicht nur GET geschickt:", set(SEEN))
print("Prüfskript: alle Fälle bestanden." if not failures else f"{failures} Fall/Fälle fehlgeschlagen.")
sys.exit(1 if failures else 0)
