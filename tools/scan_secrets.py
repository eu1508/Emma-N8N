#!/usr/bin/env python3
"""Scan repo files for accidentally committed API keys/tokens.

This is intentionally lightweight and dependency-free so it can run before every
n8n deployment. It ignores docs that intentionally describe placeholder formats,
but fails on real-looking OpenAI/Anthropic/Google/n8n/OpenRouter/Airtable tokens.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__"}
SKIP_FILES = {".env.n8n.example", "SECURITY_INCIDENT_RESPONSE.md", "WAS_DU_JETZT_MACHEN_SOLLT.md", "N8N_IMPORT_RUNBOOK.md"}
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("OpenAI API key", re.compile(r"sk-(?:proj|svcacct)-[A-Za-z0-9_-]{40,}")),
    ("OpenAI legacy key", re.compile(r"sk-[A-Za-z0-9]{32,}")),
    ("Anthropic API key", re.compile(r"sk-ant-api03-[A-Za-z0-9_-]{40,}")),
    ("OpenRouter API key", re.compile(r"sk-or-v1-[A-Fa-f0-9]{32,}")),
    ("Google API key", re.compile(r"AIza[0-9A-Za-z_-]{30,}")),
    ("Airtable PAT", re.compile(r"pat[A-Za-z0-9]{14,}\.[A-Fa-f0-9]{20,}")),
    ("n8n JWT/API token", re.compile(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}")),
]


def iter_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if not path.is_file():
            continue
        if path.name in SKIP_FILES:
            continue
        files.append(path)
    return files


def main() -> int:
    findings: list[str] = []
    for path in iter_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in PATTERNS:
            for match in pattern.finditer(text):
                rel = path.relative_to(ROOT)
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{rel}:{line}: {label}")
    if findings:
        print("Potential secrets found; rotate them and remove before commit:", file=sys.stderr)
        for finding in findings:
            print(f"- {finding}", file=sys.stderr)
        return 1
    print("No committed secret patterns found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
